`include "core_pkg.svh"
`include "rvv_pkg.svh"

module vrf_accesser
  import core_pkg::*;
  import rvv_pkg::*;
#(
  parameter int unsigned LaneId = 0
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  // interface with `vinsn_launcher`
  input  logic                           req_valid_i,
  output logic                           req_ready_o,
  input  op_req_t                        op_req_i,
  input  logic      [     InsnIDNum-1:0] insn_commit_i,
  // interface with `vfus`
  input  vrf_data_t [NrWriteBackVFU-1:0] vfu_result_wdata_i,
  input  vrf_strb_t [NrWriteBackVFU-1:0] vfu_result_wstrb_i,
  input  vrf_addr_t [NrWriteBackVFU-1:0] vfu_result_addr_i,
  input  insn_id_t  [NrWriteBackVFU-1:0] vfu_result_id_i,
  input  logic      [NrWriteBackVFU-1:0] vfu_result_valid_i,
  output logic      [NrWriteBackVFU-1:0] vfu_result_gnt_o,
  // output operands
  input  logic      [     NrOpQueue-1:0] op_ready_i,
  output logic      [     NrOpQueue-1:0] op_valid_o,
  output vrf_data_t [     NrOpQueue-1:0] operand_o,
  // vrf data access done
  output logic      [     NrOpQueue-1:0] op_access_done_o,
  output vreg_t     [     NrOpQueue-1:0] op_access_vs_o
);
  typedef enum logic {
    IDLE,
    WORKING
  } state_e;

  // part 0: shuffle req into each operand queue
  logic [NrOpQueue-1:0] op_queue_req;
  logic [NrOpQueue-1:0] op_queue_ready;
  vrf_addr_t vs1_addr, vs2_addr;
  vrf_addr_t [NrOpQueue-1:0] op_queue_req_addr;
  vreg_t [NrOpQueue-1:0] op_queue_req_vs;

  // TODO: We should generate req_ready_o based on
  // which operand queue is needed in op_req_i.
  assign req_ready_o  = (op_queue_ready & op_req_i.queue_req) == op_req_i.queue_req;
  assign op_queue_req = {NrOpQueue{req_valid_i}} & op_req_i.queue_req;

  always_comb begin
    vs1_addr                   = GetVRFAddr(op_req_i.vs1);
    vs2_addr                   = GetVRFAddr(op_req_i.vs2);
    op_queue_req_addr[ALUA]    = vs1_addr;
    op_queue_req_addr[ALUB]    = vs2_addr;
    op_queue_req_addr[StoreOp] = vs1_addr;
    op_queue_req_vs[ALUA]      = op_req_i.vs1;
    op_queue_req_vs[ALUB]      = op_req_i.vs2;
    op_queue_req_vs[StoreOp]   = op_req_i.vs1;
  end


  // part 1: generate request for each operand queue
  logic [NrOpQueue+NrWriteBackVFU-1:0] vrf_req;
  logic [NrOpQueue+NrWriteBackVFU-1:0] vrf_gnt;
  logic [NrOpQueue+NrWriteBackVFU-1:0] vrf_wen;
  bank_addr_t [NrOpQueue+NrWriteBackVFU-1:0] vrf_req_addr;
  vrf_data_t [NrOpQueue+NrWriteBackVFU-1:0] vrf_wdata;
  vrf_strb_t [NrOpQueue+NrWriteBackVFU-1:0] vrf_wstrb;
  bank_id_t [NrOpQueue+NrWriteBackVFU-1:0] bank_sel;

  for (genvar op_type = 0; op_type < NrOpQueue; op_type++) begin : gen_req
    state_e state_d, state_q;
    acc_cnt_t acc_cnt_q, acc_cnt_d;  // remained bytes
    vreg_t req_vs_d, req_vs_q;  // base register
    vrf_addr_t vrf_req_addr_q, vrf_req_addr_d;  // start address

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        // don't need to reset `vrf_req_addr_q`, `acc_cnt_q`, `req_vs_q`
        state_q <= IDLE;
      end else begin
        acc_cnt_q      <= acc_cnt_d;
        vrf_req_addr_q <= vrf_req_addr_d;
        state_q        <= state_d;
        req_vs_q       <= req_vs_d;
      end
    end

    always_comb begin
      acc_cnt_d                 = acc_cnt_q;
      req_vs_d                  = req_vs_q;
      vrf_req_addr_d            = vrf_req_addr_q;
      state_d                   = state_q;

      op_access_vs_o[op_type]   = req_vs_q;
      op_access_done_o[op_type] = 1'b0;

      // Set these signals zero for reading access
      vrf_wen[op_type]          = 'b0;
      vrf_wdata[op_type]        = 'b0;
      vrf_wstrb[op_type]        = 'b0;

      unique case (state_q)
        IDLE: begin
          op_queue_ready[op_type] = 1'b1;
          if (req_ready_o && op_queue_req[op_type]) begin
            acc_cnt_d      = op_req_i.acc_cnt;
            req_vs_d       = op_queue_req_vs[op_type];
            vrf_req_addr_d = op_queue_req_addr[op_type];
            state_d        = WORKING;
          end
        end
        WORKING: begin
          vrf_req[op_type]      = op_ready_i[op_type];
          // verilator lint_off WIDTHTRUNC
          vrf_req_addr[op_type] = vrf_req_addr_q >> $clog2(NrBank);
          // verilator lint_on WIDTHTRUNC
          bank_sel[op_type]     = vrf_req_addr_q[$clog2(NrBank)-1:0];

          if (vrf_gnt[op_type]) begin
            acc_cnt_d      = acc_cnt_q - 1;
            vrf_req_addr_d = vrf_req_addr_q + 1;
            if (acc_cnt_q == 'b1) begin
              op_access_done_o[op_type] = 1'b1;
              op_queue_ready[op_type]   = 1'b1;

              if (op_queue_req[op_type] && req_ready_o) begin
                acc_cnt_d      = op_req_i.acc_cnt;
                req_vs_d       = op_queue_req_vs[op_type];
                vrf_req_addr_d = op_queue_req_addr[op_type];
                state_d        = WORKING;
              end else begin
                state_d = IDLE;
              end
            end
          end
        end
      endcase
    end
  end : gen_req

  // part 2: generate request for each vfu
  for (genvar vfu = 0; vfu < NrWriteBackVFU; vfu++) begin : gen_vfu_req
    assign vrf_req[vfu+NrOpQueue]      = vfu_result_valid_i[vfu] && insn_commit_i[vfu_result_id_i[vfu]];
    assign vrf_wen[vfu+NrOpQueue]      = 'b1;
    // verilator lint_off WIDTHTRUNC
    assign vrf_req_addr[vfu+NrOpQueue] = vfu_result_addr_i[vfu] >> $clog2(NrBank);
    // verilator lint_on WIDTHTRUNC
    assign vrf_wdata[vfu+NrOpQueue]    = vfu_result_wdata_i[vfu];
    assign vrf_wstrb[vfu+NrOpQueue]    = vfu_result_wstrb_i[vfu];
    assign bank_sel[vfu+NrOpQueue]     = vfu_result_addr_i[vfu][$clog2(NrBank)-1:0];
    assign vfu_result_gnt_o[vfu]       = vrf_gnt[vfu+NrOpQueue];
  end : gen_vfu_req


  // Part 3: shuffle requests to each vrf bank
  logic [NrBank-1:0] arbit_bank_req;
  logic [NrBank-1:0] arbit_bank_wen;
  bank_addr_t [NrBank-1:0] arbit_bank_req_addr;
  vrf_data_t [NrBank-1:0] arbit_bank_wdata;
  vrf_strb_t [NrBank-1:0] arbit_bank_wstrb;

  logic [NrBank-1:0][NrOpQueue+NrWriteBackVFU-1:0] bank_req;
  logic [NrOpQueue+NrWriteBackVFU-1:0][NrBank-1:0] bank_req_trans;
  logic [NrBank-1:0][NrOpQueue+NrWriteBackVFU-1:0] bank_gnt;
  logic [NrOpQueue+NrWriteBackVFU-1:0][NrBank-1:0] bank_gnt_trans;
  // Generate bank request from vrf request
  always_comb begin
    for (int q = 0; q < NrOpQueue + NrWriteBackVFU; ++q) begin
      bank_req_trans[q]              = 'b0;
      bank_req_trans[q][bank_sel[q]] = vrf_req[q];
      for (int i = 0; i < NrBank; ++i) begin
        bank_req[i][q]       = bank_req_trans[q][i];
        bank_gnt_trans[q][i] = bank_gnt[i][q];
      end
      vrf_gnt[q] = |bank_gnt_trans[q];
    end
  end

  typedef struct packed {
    vrf_data_t  wdata;
    vrf_strb_t  wstrb;
    bank_addr_t addr;
    logic       wen;
  } payload_t;

  // Workaround for `rr_arb_tree` which can't handle multiple data input
  payload_t [NrOpQueue+NrWriteBackVFU-1:0] payload;
  for (genvar i = 0; i < NrOpQueue + NrWriteBackVFU; ++i) begin : gen_payload
    assign payload[i].addr  = vrf_req_addr[i];
    assign payload[i].wen   = vrf_wen[i];
    assign payload[i].wdata = vrf_wdata[i];
    assign payload[i].wstrb = vrf_wstrb[i];
  end

  // Arbitrate requests for bank conflicts
  for (genvar i = 0; i < NrBank; ++i) begin : gen_bank_req
    rr_arb_tree #(
      .NumIn    (NrOpQueue + NrWriteBackVFU),
      .DataWidth($bits(vrf_data_t) + $bits(vrf_strb_t) + $bits(bank_addr_t) + 1),
      .AxiVldRdy(1'b0)
    ) bank_req_arbiter (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .flush_i(1'b0),
      .rr_i   ('0),
      .data_i (payload),
      .req_i  (bank_req[i]),
      .gnt_o  (bank_gnt[i]),
      .data_o ({arbit_bank_wdata[i], arbit_bank_wstrb[i], arbit_bank_req_addr[i], arbit_bank_wen[i]}),
      // verilator lint_off PINCONNECTEMPTY
      .idx_o  (),
      // verilator lint_on PINCONNECTEMPTY
      .req_o  (arbit_bank_req[i]),
      .gnt_i  (arbit_bank_req[i])
    );
  end

  // assume one cycle latency of reading operation
  vrf vec_regfiles (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .req_i  (arbit_bank_req),
    .wen_i  (arbit_bank_wen),
    .addr_i (arbit_bank_req_addr),
    .wdata_i(arbit_bank_wdata),
    .wstrb_i(arbit_bank_wstrb),
    .rdata_o(rdata)
  );

  // Part 3: output operand for each queue
  vrf_data_t [NrBank-1:0] rdata;
  logic [NrOpQueue-1:0] rdata_valid_q;
  // TODO: assert `buffer_ready` should be always true.
  logic [NrOpQueue-1:0] buffer_ready;
  bank_id_t [NrOpQueue-1:0] bank_sel_q;

  for (genvar i = 0; i < NrOpQueue; i++) begin : gen_output_shuffle
    // We need a buffer to hold the operand due to the latency of reading:
    // `op_ready_i` will see valid operand one cylce later.
    // This buffer don't cut combinational path.
    fall_through_register #(
      .T(vrf_data_t)
    ) one_depth_buffer (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .clr_i     (1'b0),
      .testmode_i(1'b0),
      .data_i    (rdata[bank_sel_q[i]]),
      .valid_i   (rdata_valid_q[i]),
      .ready_o   (buffer_ready[i]),
      .data_o    (operand_o[i]),
      .valid_o   (op_valid_o[i]),
      .ready_i   (op_ready_i[i])
    );
  end : gen_output_shuffle

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_valid_q <= '0;
    end else begin
      rdata_valid_q <= vrf_gnt[NrOpQueue-1:0];
      bank_sel_q    <= bank_sel[NrOpQueue-1:0];
    end
  end

`ifdef DUMP_VRF_ACCESS
  always_ff @(posedge clk_i) begin
    for (int i = VALU; i < NrWriteBackVFU; i = i + 1) begin
      automatic vfu_e q = vfu_e'(i);
      if (vfu_result_gnt_o[i]) begin
        $display("[%0d][Lane%0d][VRFWrite] %s: addr:%0x, data:%0x, id:%0x", $time, LaneId, q.name(),
                 vfu_result_addr_i[i], vfu_result_wdata_i[i], vfu_result_id_i[i]);
      end
    end
    for (int i = ALUA; i < NrOpQueue; i = i + 1) begin
      automatic op_queue_e q = op_queue_e'(i);
      if (rdata_valid_q[i]) begin
        $display("[%0d][Lane%0d][VRFRead] %s: addr:%0x, data:%0x", $time, LaneId, q.name(), (vrf_req_addr[i] << $clog2
                 (NrBank)) + bank_sel[i] - 1, rdata[bank_sel_q[i]]);
      end
    end
  end
`endif

endmodule : vrf_accesser
