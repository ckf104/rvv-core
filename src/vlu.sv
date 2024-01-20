`include "core_pkg.svh"

// TODO: refactor into issuer-worker model
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
  // Interface with committer and scoreboard
  output logic                   done_o,
  output insn_id_t               done_insn_id_o,
  output logic                   insn_use_vd_o,
  output vreg_t                  insn_vd_o
);
  // Temporary variables
  vlen_t vstartB, vlB;
  acc_cnt_t cut_vstart, cut_vl, acc_cnt;
  word_cnt_t word_cnt;
  logic round;
  logic [LogNrLane-1:0] start_op_cnt;
  bytes_cnt_t skip_first, skip_last;

  always_comb begin : compute_initial_parameter
    vstartB      = vfu_req_i.vstart << vfu_req_i.vew_vd;
    vlB          = vfu_req_i.vl << vfu_req_i.vew_vd;

    skip_first   = vstartB[$clog2(VRFWordWidthB)-1:0];
    skip_last    = ~vlB[$clog2(VRFWordWidthB)-1:0] + 1;
    start_op_cnt = vstartB[ByteBlockWidth-1:$clog2(VRFWordWidthB)];

    word_cnt     = vlB[$bits(vlen_t)-1:$clog2(VRFWordWidthB)] - vstartB[$bits(vlen_t)-1:$clog2(VRFWordWidthB)];
    if (vlB[$clog2(VRFWordWidthB)-1:0] != 'b0) word_cnt += 1;

    cut_vstart = vstartB[$bits(vlen_t)-1:ByteBlockWidth];
    cut_vl     = vlB[$bits(vlen_t)-1:ByteBlockWidth];
    round      = vlB[ByteBlockWidth-1:0] != 'b0;
    acc_cnt    = cut_vl + round - cut_vstart;
  end : compute_initial_parameter

  typedef struct packed {
    rvv_pkg::vew_e vew_vd;
    acc_cnt_t      acc_cnt;
    // vlen_t         vstart;
    // logic [2:0]    use_vs;
    // vrf_data_t     scalar_op;
    bytes_cnt_t    skip_first;
    bytes_cnt_t    skip_last;
    insn_id_t      insn_id;
    vreg_t         vd;
  } vlu_cmd_t;
  typedef enum logic [1:0] {
    IDLE,
    LOAD
  } state_e;
  state_e state_q, state_d;

  logic [GetWidth(NrLane)-1:0] op_cnt_q, op_cnt_d;
  logic op_cnt_wrap;

  always_comb begin : sel_comb
    op_cnt_wrap = 1'b0;
    op_cnt_d    = op_cnt_q;
    if (load_op_valid_i && load_op_ready_o) begin
      op_cnt_d = op_cnt_q + 1;
      if (op_cnt_q == NrLaneMinusOne[GetWidth(NrLane)-1:0]) begin
        op_cnt_wrap = 1'b1;
        op_cnt_d    = 'b0;
      end
    end
    if (vfu_req_valid_i && vfu_req_ready_o) op_cnt_d = start_op_cnt;
  end : sel_comb

  word_cnt_t load_op_cnt_d, load_op_cnt_q;
  logic last_load_op, first_load_op_d, first_load_op_q;
  assign last_load_op = load_op_valid_i && load_op_ready_o && load_op_cnt_q == 'b1;

  always_comb begin : first_load_op
    first_load_op_d = first_load_op_q;
    if (load_op_valid_i && load_op_ready_o) first_load_op_d = 1'b0;
    if (vfu_req_valid_i && vfu_req_ready_o) first_load_op_d = 1'b1;
  end

  always_comb begin : counter
    load_op_cnt_d = load_op_cnt_q;

    if (load_op_valid_i && load_op_ready_o) load_op_cnt_d = load_op_cnt_q - 1;
    if (vfu_req_valid_i && vfu_req_ready_o) load_op_cnt_d = word_cnt;
  end

  vrf_data_t [NrLane-1:0] load_op_d, load_op_q, shuffled_load_op;
  vrf_strb_t [NrLane-1:0] load_mask_d, load_mask_q, shuffled_mask;

  // TODO: multipush_fifo to remove `load_op_q`, `load_mask_q`
  always_comb begin
    load_op_d   = load_op_q;
    load_mask_d = load_mask_q;
    if (load_op_valid_i && load_op_ready_o) begin
      if (first_load_op_q || op_cnt_q == 'b0) begin
        load_op_d   = shuffled_load_op;
        load_mask_d = shuffled_mask;
      end else begin
        load_op_d   = load_op_q | shuffled_load_op;
        load_mask_d = load_mask_q | shuffled_mask;
      end
    end
  end

  mem_shuffler_v0 mem_shuffler (
    // Input data
    .data_i    (load_op_i),
    .sel       (op_cnt_q),
    .is_first  (first_load_op_q),
    .skip_first(cmd_q.skip_first),
    .is_last   (last_load_op),
    .skip_last (cmd_q.skip_last),
    // Select one vrf word

    .sew   (cmd_q.vew_vd),
    // Output data
    .data_o(shuffled_load_op),
    .mask_o(shuffled_mask)
  );

  typedef struct packed {
    vrf_data_t data;
    vrf_strb_t mask;
  } payload_t;

  payload_t [NrLane-1:0] payload_in, payload_out;
  for (genvar i = 0; i < NrLane; ++i) begin : gen_payload
    assign payload_in[i].data = load_op_d[i];
    assign payload_in[i].mask = load_mask_d[i];
    assign load_op_o[i]       = payload_out[i].data;
    assign load_op_strb_o[i]  = payload_out[i].mask;

    assign load_op_addr_o[i]  = load_op_addr_q;
    assign load_id_o[i]       = cmd_q.insn_id;
  end

  logic outbuf_full, push, pop;
  // We may have received all of load operands even though we are in LOAD state.
  // Therefore `load_op_cnt_q != 0` is a necessary condition to assert `load_op_ready_o`.
  assign load_op_ready_o = state_q == LOAD && load_op_cnt_q != 'b0 && !outbuf_full;
  assign push            = last_load_op || op_cnt_wrap;

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

  vrf_addr_t load_op_addr_d, load_op_addr_q;

  always_comb begin : compute_addr
    load_op_addr_d = load_op_addr_q;
    if (vfu_req_valid_i && vfu_req_ready_o) load_op_addr_d = GetVRFAddr(vfu_req_i.vd) + cut_vstart;
    else if (pop) load_op_addr_d = load_op_addr_q + 1;
  end : compute_addr

  vlu_cmd_t cmd_q, cmd_d;

  always_comb begin : main_comb
    state_d         = state_q;
    cmd_d           = cmd_q;

    vfu_req_ready_o = 1'b0;
    done_o          = 1'b0;
    done_insn_id_o  = cmd_q.insn_id;
    insn_use_vd_o   = 1'b1;
    insn_vd_o       = cmd_q.vd;

    unique case (state_q)
      IDLE: begin
        vfu_req_ready_o = 1'b1;
        if (vfu_req_valid_i && target_vfu_i == VLU) begin
          cmd_d.vew_vd     = vfu_req_i.vew_vd;
          cmd_d.acc_cnt    = acc_cnt;
          cmd_d.insn_id    = vfu_req_i.insn_id;
          cmd_d.vd         = vfu_req_i.vd;
          cmd_d.skip_first = skip_first;
          cmd_d.skip_last  = skip_last;
          state_d          = LOAD;
        end
      end
      LOAD: begin
        if (pop) begin
          cmd_d.acc_cnt = cmd_q.acc_cnt - 1;
          if (cmd_q.acc_cnt == 'b1) begin
            // cmd_d.vlB = 'b0;
            done_o          = 1'b1;

            // Received `vfu_req_valid_i` depends on `vfu_req_ready_o`, therefore we
            // can't set `vfu_req_ready_o` according to `vfu_req_valid_i`.
            vfu_req_ready_o = 1'b1;
            if (vfu_req_valid_i && target_vfu_i == VLU) begin
              cmd_d.vew_vd     = vfu_req_i.vew_vd;
              cmd_d.acc_cnt    = acc_cnt;
              cmd_d.insn_id    = vfu_req_i.insn_id;
              cmd_d.vd         = vfu_req_i.vd;
              cmd_d.skip_first = skip_first;
              cmd_d.skip_last  = skip_last;
            end else state_d = IDLE;
          end
        end
      end
    endcase
  end : main_comb

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  always_ff @(posedge clk_i) begin
    load_op_q       <= load_op_d;
    load_mask_q     <= load_mask_d;
    first_load_op_q <= first_load_op_d;
    cmd_q           <= cmd_d;
    op_cnt_q        <= op_cnt_d;
    load_op_addr_q  <= load_op_addr_d;
    load_op_cnt_q   <= load_op_cnt_d;
  end

  always_ff @(posedge clk_i) begin
  end

endmodule : vlu
