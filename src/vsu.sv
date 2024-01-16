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
  input  logic                   store_op_gnt_i,
  output logic                   store_op_valid_o,
  output vrf_data_t              store_op_o,
  // Interface with committer
  input  logic                   done_gnt_i,
  output logic                   done_o,
  output insn_id_t               done_insn_id_o
);
  logic [NrLane-1:0] op_in_buf_empty, op_in_buf_full;
  logic [NrLane-1:0] store_op_valid, store_op_gnt;
  vrf_data_t [NrLane-1:0] store_op, shuffled_store_op;
  vrf_strb_t [NrLane-1:0] mask, mask_d, mask_q;

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
      .usage_o   ()
    );
  end

  logic [GetWidth(NrLane)-1:0] op_cnt_q, op_cnt_d;
  vfu_req_t vfu_req_q, vfu_req_d;

  mem_deshuffler_v1 mem_deshuffler (
    // Input data
    .data_i   (store_op),
    .bytes_cnt(vfu_req_q.vlB),
    // Select one vrf word

    .sew   (vfu_req_q.vew),
    // Output data
    .data_o(shuffled_store_op),
    .mask_o(mask)
  );

  typedef enum logic [1:0] {
    IDLE,
    STORE,
    WAIT
  } state_e;
  state_e state_q, state_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // don't need to reset `vfu_req_q`
      op_cnt_q <= 'b0;
      state_q  <= IDLE;
      mask_q   <= 'b0;
    end else begin
      vfu_req_q <= vfu_req_d;
      op_cnt_q  <= op_cnt_d;
      state_q   <= state_d;
      mask_q    <= mask_d;
    end
  end

  always_comb begin
    state_d          = state_q;
    op_cnt_d         = op_cnt_q;
    vfu_req_d        = vfu_req_q;

    vfu_req_ready_o  = 1'b0;
    store_op_valid_o = 1'b0;
    done_o           = 1'b0;
    done_insn_id_o   = vfu_req_q.insn_id;
    store_op_gnt     = 'b0;

    mask_d           = mask_q;
    if (op_cnt_q == 'b0) mask_d = mask;

    unique case (state_q)
      IDLE: begin
        vfu_req_ready_o = 1'b1;
        if (vfu_req_valid_i && target_vfu_i == VSU) begin
          vfu_req_d = vfu_req_i;
          state_d   = STORE;
        end
      end
      STORE: begin
        // TODO: we don't need to wait all lanes' operand
        store_op_valid_o = &store_op_valid;
        store_op_o       = shuffled_store_op[op_cnt_q];
        if (store_op_gnt_i) begin
          op_cnt_d = op_cnt_q + 1;
          if (op_cnt_q == NrLaneMinusOne[GetWidth(NrLane)-1:0]) begin
            store_op_gnt = {NrLane{1'b1}};
            op_cnt_d     = 'b0;
          end
          vfu_req_d.vlB = vfu_req_q.vlB - VRFWordWidthB[$bits(vlen_t)-1:0];
          if (vfu_req_q.vlB <= VRFWordWidthB[$bits(vlen_t)-1:0]) begin
            // vfu_req_d.vlB = 'b0;
            // reset operand selection signal
            op_cnt_d = 'b0;
            for (int unsigned i = 0; i < NrLane; ++i) store_op_gnt[i] = |mask_d[i];
            done_o          = 1'b1;
            // mask_d = 'b0;

            // Received `vfu_req_valid_i` depends on `vfu_req_ready_o`, therefore we
            // can't set `vfu_req_ready_o` according to `vfu_req_valid_i`.
            vfu_req_ready_o = done_gnt_i;
            if (!done_gnt_i) state_d = WAIT;
            else if (vfu_req_valid_i && target_vfu_i == VSU) vfu_req_d = vfu_req_i;
            else state_d = IDLE;
          end
        end
      end
      WAIT: begin
        done_o          = 1'b1;
        // Received `vfu_req_valid_i` depends on `vfu_req_ready_o`, therefore we
        // can't set `vfu_req_ready_o` according to `vfu_req_valid_i`.
        vfu_req_ready_o = done_gnt_i;
        if (done_gnt_i) begin
          if (vfu_req_valid_i && target_vfu_i == VSU) begin
            vfu_req_d = vfu_req_i;
            state_d   = STORE;
          end else state_d = IDLE;
        end
      end
    endcase
  end

endmodule : vsu
