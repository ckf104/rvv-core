`include "core_pkg.svh"

module vlu
  import core_pkg::*;
#(
  parameter int unsigned OutOpBufDepth = 4
) (
  input                          clk_i,
  input                          rst_ni,
  // Interface with `vinsn_launcher`
  input  logic                   vfu_req_valid_i,
  output logic                   vfu_req_ready_o,
  input  vfu_e                   target_vfu_i,
  input  vfu_req_t               vfu_req_i,
  // Interface with the scalar core
  input  logic                   load_op_valid_i,
  output logic                   load_op_ready_o,
  input  vrf_data_t              load_op_i,
  // Interface with `vrf_accesser`
  // req/gnt nameing for accesser's generating vrf req iff valid signal is asserted.
  input  logic      [NrLane-1:0] load_op_gnt_i,
  output logic      [NrLane-1:0] load_op_valid_o,
  output vrf_data_t [NrLane-1:0] load_op_o,
  output vrf_addr_t [NrLane-1:0] load_op_addr_o,
  output vrf_strb_t [NrLane-1:0] load_op_strb_o,
  output insn_id_t  [NrLane-1:0] load_id_o,
  // Interface with committer
  output logic                   done_o,
  output insn_id_t               done_insn_id_o
);
  // logic [NrLane-1:0] op_in_buf_empty, op_in_buf_full;
  logic [NrLane-1:0] load_op_valid, load_op_gnt;
  vrf_data_t [NrLane-1:0] load_op, shuffled_load_op;
  vrf_addr_t load_op_addr_d, load_op_addr_q;
  vrf_strb_t [NrLane-1:0] mask;

  logic [GetWidth(NrLane)-1:0] op_cnt_q, op_cnt_d;
  logic [NrLane-1:0] load_op_valid_demlx, load_op_ready_demlx;
  vfu_req_t vfu_req_q, vfu_req_d;

  stream_demux #(
    .N_OUP(NrLane)
  ) stream_demux (
    .inp_valid_i(load_op_valid_i),
    .inp_ready_o(load_op_ready_o),
    .oup_sel_i  (op_cnt_q),
    .oup_valid_o(load_op_valid_demlx),
    .oup_ready_i(load_op_ready_demlx)
  );

  always_comb begin : sel_comb
    op_cnt_d = op_cnt_q;
    if (load_op_valid_i && load_op_ready_o) begin
      op_cnt_d = op_cnt_q + 1;
      if (op_cnt_q == NrLaneMinusOne[GetWidth(NrLane)-1:0]) op_cnt_d = 'b0;
    end
    // TODO: here we don't assumed that scalar cpu will round vl up to ByteBlock
    if (vfu_req_valid_i && vfu_req_ready_o) op_cnt_d = 'b0;
  end : sel_comb

  // We can't assume all store operands will arrive in vsu at the same time,
  // hence four fifo have been generated.
  // Note: vrf_accesser don't launch an access until load_op_ready_o is asserted.
  for (genvar i = 0; i < NrLane; ++i) begin : gen_op_in_buf
    fall_through_register #(
      .T(vrf_data_t)
    ) alu_op_buffer (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      // TODO: unlike `vsu`, fifo in `vlu` should not be flushed?
      .clr_i     (1'b0),
      .testmode_i(1'b0),
      .data_i    (load_op_i),
      .valid_i   (load_op_valid_demlx[i]),
      .ready_o   (load_op_ready_demlx[i]),
      .data_o    (load_op[i]),
      .valid_o   (load_op_valid[i]),
      .ready_i   (load_op_gnt[i])
    );
  end

  mem_shuffler_v1 mem_shuffler (
    // Input data
    .data_i   (load_op),
    .bytes_cnt(vfu_req_q.vlB),
    // Select one vrf word

    .sew   (vfu_req_q.vew),
    // Output data
    .data_o(shuffled_load_op),
    .mask_o(mask)
  );

  typedef struct packed {
    vrf_data_t data;
    vrf_strb_t mask;
  } payload_t;

  payload_t [NrLane-1:0] payload_in, payload_out;
  for (genvar i = 0; i < NrLane; ++i) begin : gen_payload
    assign payload_in[i].data = shuffled_load_op[i];
    assign payload_in[i].mask = mask[i];
    assign load_op_o[i]       = payload_out[i].data;
    assign load_op_strb_o[i]  = payload_out[i].mask;

    assign load_op_addr_o[i]  = load_op_addr_q;
    assign load_id_o[i]       = vfu_req_q.insn_id;
  end

  logic outbuf_full, push, pop;

  always_comb begin : push_comb
    load_op_gnt = 'b0;
    push        = 1'b0;
    if (state_q == LOAD && !outbuf_full) begin
      // TODO: here we assumed that scalar cpu will round vl up to ByteBlock
      push        = &load_op_valid;
      load_op_gnt = {NrLane{push}};
    end
  end : push_comb

  multi_sync_fifo #(
    .NumFifo(NrLane),
    .Depth  (OutOpBufDepth),
    .dtype  (payload_t)
  ) multi_sync_fifo (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    // TODO: unlike `vsu`, fifo in `vlu` should not be flushed?
    .flush_i     (1'b0),
    // status flags
    .full_o      (outbuf_full),      // queue is full
    // verilator lint_off PINCONNECTEMPTY
    .empty_o     (),                 // queue is empty
    .usage_o     (),                 // fill pointer
    // verilator lint_on PINCONNECTEMPTY
    // as long as the queue is not full we can push new data
    .data_i      (payload_in),       // data to push into the queue
    .push_i      (push),             // data is valid and can be pushed to the queue
    // as long as the queue is not empty we can pop new elements
    .data_o      (payload_out),      // output data
    .data_valid_o(load_op_valid_o),
    // We assume that gnt will be asserted iff data is valid
    .gnt_i       (load_op_gnt_i),    // pop head from queue
    .pop_o       (pop)
  );

  typedef enum logic [1:0] {
    IDLE,
    LOAD
  } state_e;
  state_e state_q, state_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Don't need to reset `vfu_req_q`, `load_op_addr_q`
      op_cnt_q <= 'b0;
      state_q  <= IDLE;
    end else begin
      vfu_req_q      <= vfu_req_d;
      op_cnt_q       <= op_cnt_d;
      state_q        <= state_d;
      load_op_addr_q <= load_op_addr_d;
    end
  end

  always_comb begin : compute_addr
    load_op_addr_d = load_op_addr_q;
    if (vfu_req_valid_i && vfu_req_ready_o) load_op_addr_d = vfu_req_d.waddr;
    else if (pop) load_op_addr_d = load_op_addr_q + 1;
  end : compute_addr

  always_comb begin : main_comb
    state_d         = state_q;
    vfu_req_d       = vfu_req_q;

    vfu_req_ready_o = 1'b0;
    done_o          = 1'b0;
    done_insn_id_o  = vfu_req_q.insn_id;

    unique case (state_q)
      IDLE: begin
        vfu_req_ready_o = 1'b1;
        if (vfu_req_valid_i && target_vfu_i == VLU) begin
          vfu_req_d = vfu_req_i;
          state_d   = LOAD;
        end
      end
      LOAD: begin
        if (pop) begin
          vfu_req_d.vlB = vfu_req_q.vlB - ByteBlock[$bits(vlen_t)-1:0];
          if (vfu_req_q.vlB <= ByteBlock[$bits(vlen_t)-1:0]) begin
            // vfu_req_d.vlB = 'b0;
            done_o          = 1'b1;

            // Received `vfu_req_valid_i` depends on `vfu_req_ready_o`, therefore we
            // can't set `vfu_req_ready_o` according to `vfu_req_valid_i`.
            vfu_req_ready_o = 1'b1;
            if (vfu_req_valid_i && target_vfu_i == VLU) vfu_req_d = vfu_req_i;
            else state_d = IDLE;
          end
        end
      end
    endcase
  end : main_comb

endmodule : vlu
