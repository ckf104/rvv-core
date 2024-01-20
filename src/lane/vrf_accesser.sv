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

  typedef struct packed {
    vreg_t     base_vs;  // Register counted by scoreboard
    vrf_addr_t raddr;
    acc_cnt_t  acc_cnt;
  } opqueue_cmd_t;

  // part 0: shuffle req into each operand queue
  logic [NrOpQueue-1:0] op_queue_req;
  logic [NrOpQueue-1:0] op_queue_ready;

  // Temporary variable
  vrf_addr_t [2:0] vs_addr;
  vlen_t [2:0] vlB, vstartB;
  acc_cnt_t [2:0] cut_vl, cut_vstart, acc_cnt;
  logic [2:0] need_round;

  opqueue_cmd_t [NrOpQueue-1:0] opqueue_cmd;

  assign req_ready_o  = (op_queue_ready & op_req_i.queue_req) == op_req_i.queue_req;
  assign op_queue_req = {NrOpQueue{req_valid_i}} & op_req_i.queue_req;

  always_comb begin
    // TODO: maybe adjustment of vl and vstart could be moved into `vinsn_launcher`
    for (int unsigned i = 0; i < 3; ++i) begin
      vlB[i]        = op_req_i.vl << op_req_i.vew[i];
      vstartB[i]    = op_req_i.vstart << op_req_i.vew[i];
      cut_vl[i]     = vlB[i][$bits(vlen_t)-1:ByteBlockWidth];
      cut_vstart[i] = vstartB[i][$bits(vlen_t)-1:ByteBlockWidth];
      need_round[i] = vlB[i][ByteBlockWidth-1:0] != 'b0;
      acc_cnt[i]    = (cut_vl[i] + need_round[i]) - cut_vstart[i];
      vs_addr[i]    = GetVRFAddr(op_req_i.vs[i]) + cut_vstart[i];
    end

    // TODO: Change this shuffle into a for-loop
    opqueue_cmd[ALUA].raddr      = vs_addr[VS1];
    opqueue_cmd[ALUB].raddr      = vs_addr[VS2];
    opqueue_cmd[StoreOp].raddr   = vs_addr[VS1];

    opqueue_cmd[ALUA].base_vs    = op_req_i.vs[VS1];
    opqueue_cmd[ALUB].base_vs    = op_req_i.vs[VS2];
    opqueue_cmd[StoreOp].base_vs = op_req_i.vs[VS1];

    opqueue_cmd[ALUA].acc_cnt    = acc_cnt[VS1];
    opqueue_cmd[ALUB].acc_cnt    = acc_cnt[VS2];
    opqueue_cmd[StoreOp].acc_cnt = acc_cnt[VS1];
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
    opqueue_cmd_t cmd_d, cmd_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        // don't need to reset `cmd_q`
        state_q <= IDLE;
      end else begin
        cmd_q   <= cmd_d;
        state_q <= state_d;
      end
    end

    always_comb begin
      cmd_d                     = cmd_q;
      state_d                   = state_q;

      op_access_vs_o[op_type]   = cmd_q.base_vs;
      op_access_done_o[op_type] = 1'b0;

      vrf_req[op_type]          = 1'b0;
      vrf_req_addr[op_type]     = 'b0;  // default zero
      bank_sel[op_type]         = 'b0;  // default zero

      // Set these signals zero for reading access
      vrf_wen[op_type]          = 'b0;
      vrf_wdata[op_type]        = 'b0;  // default zero
      vrf_wstrb[op_type]        = 'b0;  // default zero

      unique case (state_q)
        IDLE: begin
          op_queue_ready[op_type] = 1'b1;
          if (req_ready_o && op_queue_req[op_type]) begin
            cmd_d   = opqueue_cmd[op_type];
            state_d = WORKING;
          end
        end
        WORKING: begin
          vrf_req[op_type]      = op_ready_i[op_type];
          // verilator lint_off WIDTHTRUNC
          vrf_req_addr[op_type] = cmd_q.raddr >> $clog2(NrBank);
          // verilator lint_on WIDTHTRUNC
          bank_sel[op_type]     = cmd_q.raddr[$clog2(NrBank)-1:0];

          if (vrf_gnt[op_type]) begin
            cmd_d.acc_cnt = cmd_q.acc_cnt - 1;
            cmd_d.raddr   = cmd_q.raddr + 1;
            if (cmd_q.acc_cnt == 'b1) begin
              op_access_done_o[op_type] = 1'b1;
              op_queue_ready[op_type]   = 1'b1;

              if (op_queue_req[op_type] && req_ready_o) begin
                cmd_d   = opqueue_cmd[op_type];
                state_d = WORKING;
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
  // Result of reading from vrf will be output after one cycle.
  // We need to remember the address of reading for dumping.
  bank_addr_t [NrOpQueue-1:0] vrf_req_addr_q;
  insn_id_t   [NrOpQueue-1:0] vrf_req_id_q;
  always_ff @(posedge clk_i) begin
    vrf_req_addr_q <= vrf_req_addr[NrOpQueue-1:0];
    for (int unsigned op_type = 0; op_type < NrOpQueue; ++op_type) begin
      if (req_ready_o && op_queue_req[op_type]) begin
        vrf_req_id_q[op_type] <= op_req_i.insn_id;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    for (int unsigned i = VALU; i < NrWriteBackVFU; i = i + 1) begin
      automatic vfu_e q = vfu_e'(i);
      if (vfu_result_gnt_o[i]) begin
        $display("[%0d][Lane%0d][VRFWrite] %s: addr:%0x, data:%x, mask:%b, id:%0x", $time, LaneId, q.name(),
                 vfu_result_addr_i[i], vfu_result_wdata_i[i], vfu_result_wstrb_i[i], vfu_result_id_i[i]);
      end
    end
    for (int unsigned i = ALUA; i < NrOpQueue; i = i + 1) begin
      automatic op_queue_e q = op_queue_e'(i);
      if (rdata_valid_q[i]) begin
        $display("[%0d][Lane%0d][VRFRead] %s: addr:%0x, data:%x, id:%0x", $time, LaneId, q.name(),
                 (vrf_req_addr_q[i] << $clog2(NrBank)) + bank_sel_q[i], rdata[bank_sel_q[i]], vrf_req_id_q[i]);
      end
    end
  end
`endif

endmodule : vrf_accesser
