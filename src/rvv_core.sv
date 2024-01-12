`include "riscv_pkg.svh"
`include "core_pkg.svh"

import riscv_pkg::xlen_t;

module rvv_core
  import core_pkg::*;
#(

) (
  input  logic                clk_i,
  input  logic                rst_ni,
  // Interface with issue logic of scalar core
  input  logic                valid_i,
  output logic                ready_o,
  input  logic         [31:0] insn_i,
  input  insn_id_t            insn_id_i,
  input  vec_context_t        vec_context_i,
  // Interface with control logic of scalar core
  input  logic                flush_i,
  input  logic                insn_can_commit_i,
  input  insn_id_t            insn_can_commit_id_i,
  // Interface with commit logic of scalar core
  output logic                done_o,
  output insn_id_t            done_insn_id_o,
  output logic                illegal_insn_o,
  output xlen_t               result_o,              // scalar results
  // Output store operands
  output logic                store_op_valid_o,
  output vrf_data_t           store_op_o,
  input  logic                store_op_gnt_i
);
  assign result_o = {$bits(xlen_t) {1'b0}};

  logic decoder_ready, launcher_ready;
  logic decoded_insn_valid, decoded_insn_illegal;
  issue_req_t decoded_insn;

  assign ready_o = decoder_ready;

  // TODO: We restrict that only one instruction can run at one time. This
  // will be fixed by hazard detecting mechanism
  logic has_running_insn_q, has_running_insn_d;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) has_running_insn_q <= 'b0;
    else has_running_insn_q <= has_running_insn_d;
  end
  always_comb begin
    has_running_insn_d = has_running_insn_q;
    if (launcher_ready && decoded_insn_valid) has_running_insn_d = 1'b1;
    if (done_o) has_running_insn_d = 1'b0;
  end

  vinsn_decoder decoder (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    // Interface with issue logic of scalar core
    .valid_i       (valid_i),
    .ready_o       (decoder_ready),
    .insn_i        (insn_i),
    .insn_id_i     (insn_id_i),
    .vec_context_i (vec_context_i),
    // Interface with `vinsn_launcher`
    .req_ready_i   (launcher_ready && !has_running_insn_q),
    .req_valid_o   (decoded_insn_valid),
    .issue_req_o   (decoded_insn),
    .illegal_insn_o(decoded_insn_illegal)
  );

  logic [NrVFU-1:0] vfu_ready;
  logic vfu_req_valid;
  vfu_req_t vfu_req;
  vfu_e target_vfu;

  logic lane_opqueue_ready;
  logic lane_opqueue_req_valid;
  op_req_t lane_opqueue_req;

  logic [NrVFU-1:0] vfu_done;
  insn_id_t [NrVFU-1:0] vfu_done_id;
  logic [NrVFU-1:0] vfu_done_gnt;

  logic [InsnIDNum-1:0] insn_can_commit;

  vinsn_launcher launcher (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    // Interface with `vinsn_decoder`
    .issue_req_valid_i   (decoded_insn_valid && !has_running_insn_q),
    .issue_req_ready_o   (launcher_ready),
    .issue_req_i         (decoded_insn),
    // Interface with `valu_wrapper`
    .vfu_req_ready_i     (vfu_ready),
    .vfu_req_valid_o     (vfu_req_valid),
    .target_vfu_o        (target_vfu),
    .vfu_req_o           (vfu_req),
    // Interface with `vrf_accesser`
    .op_req_ready_i      (lane_opqueue_ready),
    .op_req_valid_o      (lane_opqueue_req_valid),
    .op_req_o            (lane_opqueue_req),
    // Commit controller
    .insn_id_i           (insn_id_i),
    // Note: `illegal_insn_o` depends on `valid_insn_i` combinationally.
    // It will be output by decoder in the same cycle.
    .illegal_insn_i      (decoded_insn_illegal),
    .done_o              (done_o),
    .done_insn_id_o      (done_insn_id_o),
    .illegal_insn_o      (illegal_insn_o),
    .vfu_done_i          (vfu_done),
    .vfu_done_id_i       (vfu_done_id),
    .vfu_done_gnt_o      (vfu_done_gnt),
    // commit control signals used by `vrf_accesser`
    .insn_can_commit_i   (insn_can_commit_i),
    .insn_can_commit_id_i(insn_can_commit_id_i),
    .insn_can_commit_o   (insn_can_commit)
  );

  logic [NrLane-1:0] store_op_ready;
  logic [NrLane-1:0] store_op_valid;
  vrf_data_t [NrLane-1:0] store_op;

  lanes lanes (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .insn_commit_i   (insn_can_commit),
    // Interface between `vrf_accesser` and `vinsn_launcher`
    .op_req_valid_i  (lane_opqueue_req_valid),
    .op_req_ready_o  (lane_opqueue_ready),
    .op_req_i        (lane_opqueue_req),
    // Interface between `vfus` and `vinsn_launcher`
    .vfu_req_valid_i (vfu_req_valid),
    .vfu_req_ready_o (vfu_ready[NrLaneVFU-1:0]),
    .vfu_req_i       (vfu_req),
    .target_vfu_i    (target_vfu),
    // Interface between `vfus` and `vinsn_launcher`
    .vfus_done_o     (vfu_done[NrLaneVFU-1:0]),
    .vfus_done_id_o  (vfu_done_id[NrLaneVFU-1:0]),
    .vfus_done_gnt_i (vfu_done_gnt[NrLaneVFU-1:0]),
    // Output store operand
    .store_op_ready_i(store_op_ready),
    .store_op_valid_o(store_op_valid),
    .store_op_o      (store_op)
  );

  vlsu vlsu (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    // Interface with `vinsn_launcher`
    .vfu_req_valid_i (vfu_req_valid),
    .vfu_req_ready_o (vfu_ready[VLSU]),
    .target_vfu_i    (target_vfu),
    .vfu_req_i       (vfu_req),
    // Interface with `vrf_accesser`
    .store_op_valid_i(store_op_valid),
    .store_op_ready_o(store_op_ready),
    .store_op_i      (store_op),
    // Output store operands
    .store_op_gnt_i  (store_op_gnt_i),
    .store_op_valid_o(store_op_valid_o),
    .store_op_o      (store_op_o),
    // Interface with committer
    .done_gnt_i      (vfu_done_gnt[VLSU]),
    .done_o          (vfu_done[VLSU]),
    .done_insn_id_o  (vfu_done_id[VLSU])
  );




endmodule : rvv_core
