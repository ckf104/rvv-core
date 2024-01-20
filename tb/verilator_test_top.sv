`include "riscv_pkg.svh"
`include "rvv_pkg.svh"
`include "core_pkg.svh"

`ifndef MYCASE
`define GENERATE_CASE4
`endif
`include "test_case.svh"

import core_pkg::insn_id_t;
import core_pkg::vec_context_t;

typedef struct packed {
  logic [31:0]  insn;
  insn_id_t     insn_id;
  vec_context_t vec_context;
} stimulus;

module stimulus_emitter
  import core_pkg::*;
  import rvv_pkg::*;
(
  input  logic                clk_i,
  input  logic                rst_ni,
  input  logic                ready_i,
  output logic                valid_o,
  output logic         [31:0] insn_o,
  output insn_id_t            insn_id_o,
  output vec_context_t        vec_context_o,
  output logic                flush_o,
  output logic                insn_can_commit_o,
  output insn_id_t            insn_can_commit_id_o,
  // Load value
  input  logic                load_op_ready_i,
  output logic                load_op_valid_o,
  output vrf_data_t           load_op_o
);
  stimulus [NumStimulus-1:0] stim_array;
  vlen_t vl;
  vtype_t vtype;

  logic [$clog2(NumStimulus+1)-1:0] cnt_q, cnt_d, sel;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_q      <= 'b0;
      load_cnt_q <= 'b0;
    end else begin
      cnt_q      <= cnt_d;
      load_cnt_q <= load_cnt_d;
    end
  end

  vrf_data_t load_cnt_d, load_cnt_q;

  always_comb begin : load_value
    load_op_o       = load_cnt_q;
    load_cnt_d      = load_cnt_q;
    load_op_valid_o = 1'b1;
    if (load_op_ready_i && load_op_valid_o) begin
      load_cnt_d = load_cnt_q + 1;
    end
  end : load_value

  // Seperate these signals from `always_comb` to avoid
  // UNOPTFLAT warning of verilator.
  assign sel                  = valid_o ? cnt_q : 'b0;
  assign insn_o               = stim_array[sel].insn;
  assign insn_id_o            = stim_array[sel].insn_id;
  assign vec_context_o        = stim_array[sel].vec_context;
  assign insn_can_commit_o    = 1'b1;
  assign insn_can_commit_id_o = stim_array[sel].insn_id;
  assign flush_o              = 1'b0;
  assign valid_o              = cnt_q < NumStimulus;

  always_comb begin
    cnt_d = cnt_q;
    if (valid_o && ready_i) begin
      cnt_d = cnt_q + 1;
    end
  end

  initial begin
    `TEST_CASE
  end

endmodule : stimulus_emitter

module stimulus_receiver
  import core_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_ni,
  input  logic      done_i,
  input  insn_id_t  done_insn_id_i,
  input  logic      illegal_insn_i,
  input  xlen_t     result_i,
  output logic      sim_done_o,
  // Store operands
  input  logic      store_op_valid_i,
  input  vrf_data_t store_op_i,
  output logic      store_op_gnt_o
);
  logic [$clog2(NumStimulus+1)-1:0] cnt_q, cnt_d;
  int op_cnt_q, op_cnt_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_q    <= 'b0;
      op_cnt_q <= 'b0;
    end else begin
      cnt_q    <= cnt_d;
      op_cnt_q <= op_cnt_d;
    end
  end

  always_comb begin
    cnt_d      = cnt_q + done_i;
    sim_done_o = 1'b0;
    if (cnt_d == NumStimulus) begin
      sim_done_o = 1'b1;
    end
    store_op_gnt_o = 1'b0;
    op_cnt_d       = op_cnt_q;
    if (store_op_valid_i) begin
      // can't assert `gnt` unless `valid` is asserted
      store_op_gnt_o = 1'b1;
      op_cnt_d       = op_cnt_q + 1;
      $display("%d: %x", op_cnt_q, store_op_i);
    end
  end

endmodule

module verilator_test_top
  import core_pkg::*;
  import riscv_pkg::xlen_t;
(
  input logic clk_i,
  input logic rst_ni
);
  logic valid, ready;
  logic [31:0] insn;
  insn_id_t insn_id;
  vec_context_t vec_context;
  logic flush;
  logic insn_can_commit;
  insn_id_t insn_can_commit_id;

  logic done, sim_done;
  insn_id_t done_insn_id;
  logic illegal_insn;
  xlen_t result;

  logic load_op_valid, load_op_ready;
  vrf_data_t load_op;

  stimulus_emitter emitter (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .ready_i             (ready),
    .valid_o             (valid),
    .insn_o              (insn),
    .insn_id_o           (insn_id),
    .vec_context_o       (vec_context),
    .flush_o             (flush),
    .insn_can_commit_o   (insn_can_commit),
    .insn_can_commit_id_o(insn_can_commit_id),
    // Output load value
    .load_op_ready_i     (load_op_ready),
    .load_op_valid_o     (load_op_valid),
    .load_op_o           (load_op)
  );

  logic store_op_valid, store_op_gnt;
  vrf_data_t store_op;

  stimulus_receiver receiver (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .done_i          (done),
    .done_insn_id_i  (done_insn_id),
    .illegal_insn_i  (illegal_insn),
    .result_i        (result),
    .sim_done_o      (sim_done),
    // Store operands
    .store_op_valid_i(store_op_valid),
    .store_op_i      (store_op),
    .store_op_gnt_o  (store_op_gnt)
  );

  rvv_core rvv_core (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    // Interface with issue logic of scalar core
    .valid_i             (valid),
    .ready_o             (ready),
    .insn_i              (insn),
    .insn_id_i           (insn_id),
    .vec_context_i       (vec_context),
    .scalar_reg_i        ('b0),
    // Interface with control logic of scalar core
    .flush_i             (flush),
    .insn_can_commit_i   (insn_can_commit),
    .insn_can_commit_id_i(insn_can_commit_id),
    // Interface with commit logic of scalar core
    .done_o              (done),
    .done_insn_id_o      (done_insn_id),
    .illegal_insn_o      (illegal_insn),
    // scalar results
    .result_o            (result),
    // Output store operands
    .store_op_valid_o    (store_op_valid),
    .store_op_o          (store_op),
    .store_op_ready_i    (store_op_gnt),
    // Load input operands
    .load_op_valid_i     (load_op_valid),
    .load_op_ready_o     (load_op_ready),
    .load_op_i           (load_op)
  );

  always_ff @(posedge clk_i) begin
    if (sim_done) begin
      //$display("%d", rvv_core.lane.accesser.vec_regfiles.gen_banks[0].vrf_sram.sram[0]);
      $finish(0);
    end
  end
  initial begin
    $dumpfile("./core.fst");
    $dumpvars();
  end
endmodule : verilator_test_top
