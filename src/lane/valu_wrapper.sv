`include "core_pkg.svh"

module valu_wrapper
  import core_pkg::*;
  import rvv_pkg::*;
#(
  parameter int unsigned LaneId         = 0,
  parameter int unsigned ALUOpBufDepth  = 4,
  parameter int unsigned ALUReqBufDepth = 2,
  parameter int unsigned ALUWBufDepth   = 2
) (
  input  logic            clk_i,
  input  logic            rst_ni,
  // interface with `vinsn_launcher`
  input  logic            vfu_req_valid_i,
  output logic            vfu_req_ready_o,
  input  vfu_req_t        vfu_req_i,
  input  vfu_e            target_vfu_i,
  // interface with `vinsn_launcher`
  output logic            alu_done_o,
  output insn_id_t        alu_done_id_o,
  output logic            alu_use_vd_o,
  output vreg_t           alu_vd_o,
  // interface with `vrf_accesser`
  input  logic      [1:0] op_valid_i,
  output logic      [1:0] op_ready_o,
  input  vrf_data_t [1:0] alu_op_i,
  // interface with `vrf_accesser`
  output vrf_data_t       alu_result_wdata_o,
  output vrf_strb_t       alu_result_wstrb_o,
  output vrf_addr_t       alu_result_addr_o,
  output insn_id_t        alu_result_id_o,
  output logic            alu_result_valid_o,
  input  logic            alu_result_gnt_i
);
  logic [1:0] op_buf_full, op_buf_empty, op_buf_pop;
  vrf_data_t [1:0] alu_buf_operand, alu_operand;
  // TODO: Use lane_vlen_t to replace vlen_t

  assign op_ready_o = ~op_buf_full;

  for (genvar i = 0; i < 2; ++i) begin : gen_op_buf
    // Generally, our coding style has each module output its signal early(
    // i.e., pipeline registers delay one cycle of output). But here We expect
    // that `alu_op` will not arrive early in this cycle for sram reading and
    // shuffle delay.
    fifo_v3 #(
      .DEPTH     (ALUOpBufDepth),
      .DATA_WIDTH($bits(vrf_data_t))
    ) alu_op_buffer (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .testmode_i(1'b0),
      .flush_i   (1'b0),
      .data_i    (alu_op_i[i]),
      .push_i    (op_valid_i[i]),
      .full_o    (op_buf_full[i]),
      .data_o    (alu_buf_operand[i]),
      .pop_i     (op_buf_pop[i]),
      .empty_o   (op_buf_empty[i]),
      // verilator lint_off PINCONNECTEMPTY
      .usage_o   ()
      // verilator lint_on PINCONNECTEMPTY
    );
  end : gen_op_buf

  typedef enum logic {
    ISSUE,
    COMMIT
  } worker_e;
  localparam int unsigned NrWorker = 2;

  typedef struct packed {
    vop_e          vop;
    rvv_pkg::vew_e vew_vd;
    vrf_addr_t     waddr;
    acc_cnt_t      acc_cnt;
    ele_cnt_t      skip_first_cnt;
    ele_cnt_t      skip_last_cnt;
    logic [2:0]    use_vs;
    vrf_data_t     scalar_op;
    insn_id_t      insn_id;
    vreg_t         vd;
  } alu_cmd_t;

  alu_cmd_t [NrWorker-1:0] out_req;
  logic [NrWorker-1:0] no_req, worker_done;
  alu_cmd_t in_req;
  logic push_req, req_buf_full;

  // ALU instruction has been done if commit worker completes its work
  assign alu_done_o    = worker_done[COMMIT];
  assign alu_done_id_o = out_req[COMMIT].insn_id;
  assign alu_use_vd_o  = 1'b1;  // ALU always writes back.
  assign alu_vd_o      = out_req[COMMIT].vd;

  multiport_fifo #(
    .NrReadPort(NrWorker),
    .Depth     (ALUReqBufDepth),
    .dtype     (alu_cmd_t)
  ) vfu_req_fifo (
    .clk_i  (clk_i),         // Clock
    .rst_ni (rst_ni),        // Asynchronous reset active low
    // TODO: flush support
    .flush_i(1'b0),          // flush the queue
    // status flags
    .full_o (req_buf_full),  // queue is full
    .empty_o(no_req),        // queue is empty
    // verilator lint_off PINCONNECTEMPTY
    .usage_o(),
    // verilator lint_on PINCONNECTEMPTY
    // as long as the queue is not full we can push new data
    .data_i (in_req),        // data to push into the queue
    .push_i (push_req),      // data is valid and can be pushed to the queue
    // as long as the queue is not empty we can pop new elements
    .data_o (out_req),       // output data
    .pop_i  (worker_done)    // forward the read pointer
  );

  // Temporary variables
  vlen_t vl_in_lane, vstart_in_lane, vlB_in_lane, vstartB_in_lane;
  vlen_t vstartB_in_opqueue, vlB_in_opqueue;
  acc_cnt_t cut_vl, cut_vstart, acc_cnt;
  ele_cnt_t skip_first, skip_last;

  // `vfu_req_valid_i` depends on `vfu_req_ready_o`, removing `vfu_req_ready_o`
  // from `always_comb` to avoid UNOPTFLAT warning of verilator
  assign vfu_req_ready_o = ~req_buf_full;
  always_comb begin : accept_new_req
    vl_in_lane = vfu_req_i.vl >> LogNrLane;
    if (vfu_req_i.vl[LogNrLane-1:0] > LaneId[LogNrLane-1:0]) vl_in_lane += 1;
    vstart_in_lane = vfu_req_i.vstart >> LogNrLane;
    if (vfu_req_i.vstart[LogNrLane-1:0] > LaneId[LogNrLane-1:0]) vstart_in_lane += 1;

    vlB_in_lane        = vl_in_lane << vfu_req_i.vew_vd;
    vstartB_in_lane    = vstart_in_lane << vfu_req_i.vew_vd;

    vstartB_in_opqueue = vfu_req_i.vstart << vfu_req_i.vew_vd;
    vstartB_in_opqueue = (vstartB_in_opqueue >> ByteBlockWidth) << ByteBlockWidth;
    vstartB_in_opqueue = vstartB_in_opqueue >> LogNrLane;

    vlB_in_opqueue     = vfu_req_i.vl << vfu_req_i.vew_vd;
    if (vlB_in_opqueue[ByteBlockWidth-1:0] != 'b0) begin
      vlB_in_opqueue = {vlB_in_opqueue[$bits(vlen_t)-1:ByteBlockWidth] + 1'b1, {ByteBlockWidth{1'b0}}};
    end
    vlB_in_opqueue        = vlB_in_opqueue >> LogNrLane;

    cut_vl                = vlB_in_opqueue[LaneVLWidth-1:$clog2(VRFWordWidthB)];
    cut_vstart            = vstartB_in_opqueue[LaneVLWidth-1:$clog2(VRFWordWidthB)];
    acc_cnt               = cut_vl - cut_vstart;

    skip_first            = vstartB_in_lane - vstartB_in_opqueue;
    skip_last             = vlB_in_opqueue - vlB_in_lane;

    // OK, we can fill in_req with above temporary variables
    push_req              = vfu_req_valid_i && vfu_req_ready_o && target_vfu_i == VALU;
    in_req.vop            = vfu_req_i.vop;
    in_req.vew_vd         = vfu_req_i.vew_vd;
    in_req.waddr          = GetVRFAddr(vfu_req_i.vd) + cut_vstart;
    in_req.acc_cnt        = acc_cnt;
    in_req.skip_first_cnt = skip_first;
    in_req.skip_last_cnt  = skip_last;
    in_req.use_vs         = vfu_req_i.use_vs;
    in_req.scalar_op      = vfu_req_i.scalar_op;
    in_req.insn_id        = vfu_req_i.insn_id;
    in_req.vd             = vfu_req_i.vd;
  end



  alu_cmd_t issuing_req;
  assign issuing_req = out_req[ISSUE];

  logic issuing_req_valid, issuing_done;
  assign issuing_req_valid  = ~no_req[ISSUE];
  assign worker_done[ISSUE] = issuing_done;

  acc_cnt_t issue_cnt_d, issue_cnt_q;

  vrf_data_t scalar_op;
  logic [1:0] alu_operand_valid;
  always_comb begin : issue_alu_operand
    unique case (issuing_req.vew_vd)
      EW64: scalar_op = {1{issuing_req.scalar_op[63:0]}};
      EW32: scalar_op = {2{issuing_req.scalar_op[31:0]}};
      EW16: scalar_op = {4{issuing_req.scalar_op[15:0]}};
      EW8:  scalar_op = {8{issuing_req.scalar_op[7:0]}};
    endcase
    alu_operand[0]       = issuing_req.use_vs[0] ? alu_buf_operand[0] : scalar_op;
    alu_operand[1]       = alu_buf_operand[1];

    alu_operand_valid[0] = issuing_req.use_vs[0] ? ~op_buf_empty[0] : 1'b1;
    alu_operand_valid[1] = issuing_req.use_vs[1] ? ~op_buf_empty[1] : 1'b1;
  end : issue_alu_operand

  logic result_buf_full;  // whether result buffer is full
  logic alu_result_valid;  // new alu result
  // whether this is the first result of an alu instruction
  logic is_first_issue_d, is_first_issue_q;
  acc_cnt_t issue_selected_cnt;
  assign issue_selected_cnt = is_first_issue_q ? issuing_req.acc_cnt : issue_cnt_q;

  always_comb begin : issue_main_logic
    issue_cnt_d      = issue_cnt_q;
    is_first_issue_d = is_first_issue_q;
    issuing_done     = 1'b0;

    alu_result_valid = 1'b0;
    op_buf_pop       = 'b0;

    // We can issue an alu computing if `issuing_req` is valid, both operands
    // are ready, result buffer is not full.
    if (issuing_req_valid && &alu_operand_valid && !result_buf_full) begin
      alu_result_valid = 1'b1;
      is_first_issue_d = 1'b0;
      op_buf_pop[0]    = issuing_req.use_vs[0];
      op_buf_pop[1]    = issuing_req.use_vs[1];

      issue_cnt_d      = issue_selected_cnt - 1;
      if (issue_selected_cnt == 'b1) begin
        issuing_done     = 1'b1;
        is_first_issue_d = 1'b1;
      end
    end
  end : issue_main_logic

  always_ff @(posedge clk_i or negedge rst_ni) begin
    // don't need to reset `issue_cnt_q`
    if (!rst_ni) begin
      is_first_issue_q <= 1'b1;
    end else begin
      is_first_issue_q <= is_first_issue_d;
      issue_cnt_q      <= issue_cnt_d;
    end
  end

  alu_cmd_t committing_req;
  assign committing_req = out_req[COMMIT];

  logic committing_req_valid, committing_done;
  assign committing_req_valid = ~no_req[COMMIT];
  assign worker_done[COMMIT]  = committing_done;

  acc_cnt_t commit_cnt_d, commit_cnt_q;
  logic is_first_commit_d, is_first_commit_q;
  acc_cnt_t commit_selected_cnt;
  assign commit_selected_cnt = is_first_commit_q ? committing_req.acc_cnt : commit_cnt_q;

  vrf_addr_t wb_addr_d, wb_addr_q;  // writeback addr
  vrf_addr_t selected_wb_addr;
  assign selected_wb_addr = is_first_commit_q ? committing_req.waddr : wb_addr_q;

  always_comb begin : main_commit_logic
    commit_cnt_d      = commit_cnt_q;
    wb_addr_d         = wb_addr_q;
    is_first_commit_d = is_first_commit_q;
    committing_done   = 1'b0;

    if (alu_result_gnt_i) begin
      is_first_commit_d = 1'b0;
      commit_cnt_d      = commit_selected_cnt - 1;
      wb_addr_d         = selected_wb_addr + 1;
      if (commit_selected_cnt == 'b1) begin
        is_first_commit_d = 1'b1;
        committing_done   = 1'b1;
      end
    end
  end : main_commit_logic

  always_ff @(posedge clk_i or negedge rst_ni) begin
    // don't need to reset `commit_cnt_q`, `wb_addr_q`
    if (!rst_ni) begin
      is_first_commit_q <= 1'b1;
    end else begin
      is_first_commit_q <= is_first_commit_d;
      commit_cnt_q      <= commit_cnt_d;
      wb_addr_q         <= wb_addr_d;
    end
  end

  vrf_data_t alu_result;
  vrf_strb_t alu_result_mask;

  valu vec_alu (
    .operand_i(alu_operand),
    .vew_i    (issuing_req.vew_vd),
    .op_i     (issuing_req.vop),
    .result_o (alu_result)
  );
  mask_generator_v1 #(
    .MaskWidth(VRFWordWidthB)
  ) mask_generator (
    .first_req_i (is_first_issue_q),
    .last_req_i  (issuing_done),
    .skip_first_i(issuing_req.skip_first_cnt),
    .skip_last_i (issuing_req.skip_last_cnt),
    .mask_o      (alu_result_mask)
  );

  typedef struct packed {
    vrf_data_t data;
    vrf_strb_t mask;
  } payload_t;

  payload_t payload_in, payload_out;
  assign payload_in.data = alu_result;
  assign payload_in.mask = alu_result_mask;

  logic result_buf_empty;

  fifo_v3 #(
    .DEPTH     (ALUWBufDepth),
    .DATA_WIDTH($bits(payload_t))
  ) alu_result_buffer (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .testmode_i(1'b0),
    .flush_i   (1'b0),
    .data_i    (payload_in),
    .push_i    (alu_result_valid),
    .full_o    (result_buf_full),
    .data_o    (payload_out),
    .pop_i     (alu_result_gnt_i),
    .empty_o   (result_buf_empty),
    // verilator lint_off PINCONNECTEMPTY
    .usage_o   ()
    // verilator lint_on PINCONNECTEMPTY
  );

  assign alu_result_valid_o = !result_buf_empty;
  assign alu_result_addr_o  = selected_wb_addr;
  assign alu_result_id_o    = committing_req.insn_id;
  assign alu_result_wdata_o = payload_out.data;
  assign alu_result_wstrb_o = payload_out.mask;

endmodule : valu_wrapper
