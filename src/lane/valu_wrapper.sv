`include "core_pkg.svh"

module valu_wrapper
  import core_pkg::*;
  import rvv_pkg::*;
#(
  parameter int unsigned ALUOpBufDepth = 4,
  parameter int unsigned ALUWBufDepth  = 2
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
  input  logic            alu_done_gnt_i,
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
  typedef enum logic [1:0] {
    IDLE,
    WORKING,
    WAITING
  } state_e;
  state_e state_q, state_d;

  logic [1:0] op_buf_full, op_buf_empty;
  logic [1:0] alu_operand_valid;
  logic result_buf_empty, result_buf_full;
  logic alu_result_valid;
  vrf_data_t [1:0] alu_buf_operand, alu_operand;
  vrf_data_t alu_result;
  // TODO: Use a req buffer to separate operation issue from result commit
  // TODO: Use lane_vlen_t to replace vlen_t
  vfu_req_t vfu_req_q, vfu_req_d;
  vlen_t commit_cnt_q, commit_cnt_d;

  assign op_ready_o        = ~op_buf_full;
  assign alu_operand_valid = ~op_buf_empty;

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
      .pop_i     (alu_result_valid && vfu_req_d.use_vs[i]),
      .empty_o   (op_buf_empty[i]),
      .usage_o   ()
    );
  end : gen_op_buf

  always_comb begin
    vfu_req_d        = vfu_req_q;
    vfu_req_ready_o  = 1'b0;
    alu_done_o       = 1'b0;
    alu_done_id_o    = vfu_req_q.insn_id;
    alu_result_valid = 1'b0;
    commit_cnt_d     = commit_cnt_q;

    unique case (state_q)
      IDLE: begin
        vfu_req_ready_o = 1'b1;
        if (vfu_req_valid_i && target_vfu_i == VALU) begin
          vfu_req_d     = vfu_req_i;
          vfu_req_d.vlB = vfu_req_i.vlB >> LogNrLane;
          commit_cnt_d  = vfu_req_d.vlB;
          state_d       = WORKING;
        end
      end
      WORKING: begin
        if ((alu_operand_valid[0] || !vfu_req_q.use_vs[0]) && (alu_operand_valid[1] || !vfu_req_q.use_vs[1]) &&
            !result_buf_full && commit_cnt_q != 'b0) begin
          alu_result_valid = 1'b1;
          commit_cnt_d     = commit_cnt_q - VRFWordWidthB[$bits(vlen_t)-1:0];
          if (commit_cnt_q <= VRFWordWidthB[$bits(vlen_t)-1:0]) begin
            commit_cnt_d = 'b0;
          end
        end
        if (alu_result_gnt_i) begin
          vfu_req_d.waddr = vfu_req_q.waddr + 1;
          vfu_req_d.vlB   = vfu_req_q.vlB - VRFWordWidthB[$bits(vlen_t)-1:0];
          if (vfu_req_q.vlB <= VRFWordWidthB[$bits(vlen_t)-1:0]) begin
            alu_done_o = 1'b1;
            if (!alu_done_gnt_i) begin
              state_d = WAITING;
            end else if (vfu_req_valid_i && target_vfu_i == VALU) begin
              vfu_req_d     = vfu_req_i;
              vfu_req_d.vlB = vfu_req_i.vlB >> LogNrLane;
              commit_cnt_d  = vfu_req_d.vlB;
            end else begin
              state_d = IDLE;
            end
          end
        end
      end
      WAITING: begin
        alu_done_o = 1'b1;
        if (alu_done_gnt_i) begin
          if (vfu_req_valid_i && target_vfu_i == VALU) begin
            vfu_req_d     = vfu_req_i;
            vfu_req_d.vlB = vfu_req_i.vlB >> LogNrLane;
            commit_cnt_d  = vfu_req_d.vlB;
            state_d       = WORKING;
          end else begin
            state_d = IDLE;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // don't need to reset `vfu_req_q`
      state_q <= IDLE;

    end else begin
      state_q      <= state_d;
      vfu_req_q    <= vfu_req_d;
      commit_cnt_q <= commit_cnt_d;
    end
  end



  vrf_data_t scalar_op;
  always_comb begin
    unique case (vfu_req_q.vew)
      EW64: scalar_op = {1{vfu_req_q.scalar_op[63:0]}};
      EW32: scalar_op = {2{vfu_req_q.scalar_op[31:0]}};
      EW16: scalar_op = {4{vfu_req_q.scalar_op[15:0]}};
      EW8:  scalar_op = {8{vfu_req_q.scalar_op[7:0]}};
    endcase
    alu_operand[0] = vfu_req_q.use_vs[0] ? alu_buf_operand[0] : scalar_op;
    alu_operand[1] = alu_buf_operand[1];
  end

  valu vec_alu (
    .operand_i(alu_operand),
    .vew_i    (vfu_req_q.vew),
    .op_i     (vfu_req_q.vop),
    .result_o (alu_result)
  );

  fifo_v3 #(
    .DEPTH     (ALUWBufDepth),
    .DATA_WIDTH($bits(vrf_data_t))
  ) alu_result_buffer (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .testmode_i(1'b0),
    .flush_i   (1'b0),
    .data_i    (alu_result),
    .push_i    (alu_result_valid),
    .full_o    (result_buf_full),
    .data_o    (alu_result_wdata_o),
    .pop_i     (alu_result_gnt_i),
    .empty_o   (result_buf_empty),
    .usage_o   ()
  );

  assign alu_result_valid_o = !result_buf_empty;
  assign alu_result_addr_o  = vfu_req_q.waddr;
  assign alu_result_id_o    = vfu_req_q.insn_id;
  // TODO: support mask for non-aligned vl
  assign alu_result_wstrb_o = {$bits(vrf_strb_t) {1'b1}};

endmodule : valu_wrapper
