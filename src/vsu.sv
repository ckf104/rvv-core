`include "core_pkg.svh"

module vsu
  import core_pkg::*;
#(
  parameter int unsigned InOpBufDepth = 4
) (
  input                          clk_i,
  input                          rst_ni,
  // Interface with `vinsn_launcher`
  input  logic                   vfu_req_valid_i,
  output logic                   vfu_req_ready_o,
  input  vfu_e                   target_vfu_i,
  input  vfu_req_t               vfu_req_i,
  // Interface with `vrf_accesser`
  // Must be valid/ready interface instead of req/gnt, accesser
  // only generates vrf req when ready signal is asserted.
  input  logic      [NrLane-1:0] store_op_valid_i,
  output logic      [NrLane-1:0] store_op_ready_o,
  input  vrf_data_t [NrLane-1:0] store_op_i,
  // Output store operands
  input  logic                   store_op_ready_i,
  output logic                   store_op_valid_o,
  output vrf_data_t              store_op_o,
  // Interface with committer
  output logic                   done_o,
  output insn_id_t               done_insn_id_o,
  output logic                   insn_use_vd_o,
  output vreg_t                  insn_vd_o
);
  logic acc_new_req;
  assign acc_new_req = vfu_req_ready_o && vfu_req_valid_i && target_vfu_i == VSU;
  logic store_op_fired;
  assign store_op_fired = store_op_valid_o && store_op_ready_i;

  // Temporary variables
  vlen_t vstartB, vlB;
  // acc_cnt_t cut_vstart, cut_vl, acc_cnt;
  word_cnt_t word_cnt;
  // logic round;
  logic [GetWidth(NrLane)-1:0] start_op_cnt;
  // logic [ByteBlockWidth-1:0] skip_first, skip_last;

  always_comb begin : compute_initial_parameter
    vstartB = vfu_req_i.vstart << vfu_req_i.vew_vd;
    vlB     = vfu_req_i.vl << vfu_req_i.vew_vd;

    // skip_first = vstartB[ByteBlockWidth-1:0];
    // skip_last  = ~vlB[ByteBlockWidth-1:0] + 1;

    if (NrLane == 1) start_op_cnt = 1'b0;
    else start_op_cnt = vstartB[ByteBlockWidth-1:$clog2(VRFWordWidthB)];

    word_cnt = vlB[$bits(vlen_t)-1:$clog2(VRFWordWidthB)] - vstartB[$bits(vlen_t)-1:$clog2(VRFWordWidthB)];
    if (vlB[$clog2(VRFWordWidthB)-1:0] != 'b0) word_cnt += 1;

    // cut_vstart = vstartB[$bits(vlen_t)-1:ByteBlockWidth];
    // cut_vl     = vlB[$bits(vlen_t)-1:ByteBlockWidth];
    // round      = vlB[ByteBlockWidth-1:0] != 'b0;
    // acc_cnt    = cut_vl + round - cut_vstart;
  end : compute_initial_parameter

  typedef struct packed {
    rvv_pkg::vew_e vew;
    word_cnt_t     word_cnt;
    // vlen_t         vstart;
    // logic [2:0]    use_vs;
    // vrf_data_t     scalar_op;
    // logic [ByteBlockWidth-1:0] skip_first;
    // logic [ByteBlockWidth-1:0] skip_last;
    insn_id_t      insn_id;
    // vreg_t         vd;
  } vsu_cmd_t;

  logic [NrLane-1:0] op_in_buf_empty, op_in_buf_full;
  logic [NrLane-1:0] store_op_valid, store_op_gnt;
  vrf_data_t [NrLane-1:0] store_op, shuffled_store_op;
  // vrf_strb_t [NrLane-1:0] mask, mask_d, mask_q;

  assign store_op_ready_o = ~op_in_buf_full;
  assign store_op_valid   = ~op_in_buf_empty;

  // We can't assume all store operands will arrive in vsu at the same time,
  // hence four fifo have been generated.
  // Note: vrf_accesser don't launch an access until store_op_ready_o is asserted.
  for (genvar i = 0; i < NrLane; ++i) begin : gen_op_in_buf
    fifo_v3 #(
      .DEPTH     (InOpBufDepth),
      .DATA_WIDTH($bits(vrf_data_t))
    ) alu_op_buffer (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .testmode_i(1'b0),
      // TODO: we need to flush the fifo when exception occurs
      .flush_i   (1'b0),
      .data_i    (store_op_i[i]),
      .push_i    (store_op_valid_i[i]),
      .full_o    (op_in_buf_full[i]),
      .data_o    (store_op[i]),
      .pop_i     (store_op_gnt[i]),
      .empty_o   (op_in_buf_empty[i]),
      // verilator lint_off PINCONNECTEMPTY
      .usage_o   ()
      // verilator lint_on PINCONNECTEMPTY
    );
  end

  logic [GetWidth(NrLane)-1:0] op_cnt_q, op_cnt_d;
  logic op_cnt_wrap;
  assign store_op_gnt = {NrLane{op_cnt_wrap | done_o}};

  always_comb begin : op_cnt_logic
    op_cnt_wrap = 1'b0;
    op_cnt_d    = op_cnt_q;
    if (store_op_fired) begin
      op_cnt_d = op_cnt_q + 1;
      if (op_cnt_q == NrLaneMinusOne[GetWidth(NrLane)-1:0]) begin
        op_cnt_wrap = 1'b1;
        op_cnt_d    = 'b0;
      end
    end
    if (acc_new_req) op_cnt_d = start_op_cnt;
  end : op_cnt_logic

  vsu_cmd_t cmd_q, cmd_d;

  mem_deshuffler_v0 mem_deshuffler (
    // Input data
    .data_i    (store_op),
    .is_first  ('b0),
    .skip_first('b0),
    .is_last   ('b0),
    .skip_last ('b0),
    .sew       (cmd_q.vew),
    // Output data
    .data_o    (shuffled_store_op),
    // verilator lint_off PINCONNECTEMPTY
    .mask_o    ()
    // verilator lint_on PINCONNECTEMPTY
  );

  typedef enum logic [1:0] {
    IDLE,
    STORE
  } state_e;
  state_e state_q, state_d;



  always_comb begin
    state_d          = state_q;
    cmd_d            = cmd_q;

    vfu_req_ready_o  = 1'b0;
    store_op_valid_o = 1'b0;
    done_o           = 1'b0;
    done_insn_id_o   = cmd_q.insn_id;
    insn_use_vd_o    = 1'b0;  // Store instruction don't write back
    insn_vd_o        = 'b0;

    unique case (state_q)
      IDLE: begin
        vfu_req_ready_o = 1'b1;
        if (vfu_req_valid_i && target_vfu_i == VSU) begin
          cmd_d.vew      = vfu_req_i.vew_vd;
          cmd_d.word_cnt = word_cnt;
          cmd_d.insn_id  = vfu_req_i.insn_id;
          state_d        = STORE;
        end
      end
      STORE: begin
        // TODO: we don't need to wait all lanes' operand
        store_op_valid_o = &store_op_valid;
        store_op_o       = shuffled_store_op[op_cnt_q];
        if (store_op_fired) begin
          cmd_d.word_cnt = cmd_q.word_cnt - 1;
          if (cmd_q.word_cnt == 'b1) begin
            done_o          = 1'b1;
            // Received `vfu_req_valid_i` depends on `vfu_req_ready_o`, therefore we
            // can't set `vfu_req_ready_o` according to `vfu_req_valid_i`.
            vfu_req_ready_o = 1'b1;
            if (vfu_req_valid_i && target_vfu_i == VSU) begin
              cmd_d.vew      = vfu_req_i.vew_vd;
              cmd_d.word_cnt = word_cnt;
              cmd_d.insn_id  = vfu_req_i.insn_id;
            end else state_d = IDLE;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  always_ff @(posedge clk_i) begin
    cmd_q    <= cmd_d;
    op_cnt_q <= op_cnt_d;
  end

endmodule : vsu
