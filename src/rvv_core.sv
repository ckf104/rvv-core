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
  input  xlen_t               scalar_reg_i,
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
  input  logic                store_op_ready_i,
  // Input load values
  input  logic                load_op_valid_i,
  input  vrf_data_t           load_op_i,
  output logic                load_op_ready_o
);
  assign result_o = {$bits(xlen_t) {1'b0}};

  logic decoder_ready, launcher_ready;
  logic decoded_insn_valid, decoded_insn_illegal;
  issue_req_t decoded_insn;

  assign ready_o = decoder_ready;

  vinsn_decoder decoder (
    // .clk_i         (clk_i),
    // .rst_ni        (rst_ni),
    // Interface with issue logic of scalar core
    .valid_i       (valid_i),
    .ready_o       (decoder_ready),
    .insn_i        (insn_i),
    .insn_id_i     (insn_id_i),
    .vec_context_i (vec_context_i),
    // Interface with `vinsn_launcher`
    .req_ready_i   (launcher_ready),
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

  logic [NrVFU-1:0] vfu_done, vfu_use_vd;
  insn_id_t [NrVFU-1:0] vfu_done_id;
  vreg_t [NrVFU-1:0] vfu_vd;

  logic [NrOpQueue-1:0] op_access_done;
  vreg_t [NrOpQueue-1:0] op_access_vs;

  logic [InsnIDNum-1:0] insn_can_commit;

  vinsn_launcher launcher (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    // Interface with `vinsn_decoder`
    .issue_req_valid_i   (decoded_insn_valid),
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
    // done signals from vfus and `vrf_accessser`
    .vfu_done_i          (vfu_done),
    .vfu_done_id_i       (vfu_done_id),
    .vfu_use_vd_i        (vfu_use_vd),
    .vfu_vd_i            (vfu_vd),
    .op_access_done_i    (op_access_done),
    .op_access_vs_i      (op_access_vs),
    // commit control signals used by `vrf_accesser`
    .insn_can_commit_i   (insn_can_commit_i),
    .insn_can_commit_id_i(insn_can_commit_id_i),
    .insn_can_commit_o   (insn_can_commit)
  );

  logic [NrLane-1:0] store_op_ready;
  logic [NrLane-1:0] store_op_valid;
  vrf_data_t [NrLane-1:0] store_op;

  logic [NrLane-1:0] load_op_valid;
  logic [NrLane-1:0] load_op_gnt;
  vrf_data_t [NrLane-1:0] load_op;
  vrf_strb_t [NrLane-1:0] load_op_strb;
  vrf_addr_t [NrLane-1:0] load_op_addr;
  insn_id_t [NrLane-1:0] load_id;

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
    .vfus_use_vd_o   (vfu_use_vd[NrLaneVFU-1:0]),
    .vfus_vd_o       (vfu_vd[NrLaneVFU-1:0]),
    .op_access_done_o(op_access_done),
    .op_access_vs_o  (op_access_vs),
    // Output store operand
    .store_op_ready_i(store_op_ready),
    .store_op_valid_o(store_op_valid),
    .store_op_o      (store_op),
    // Input load value
    .load_op_gnt_o   (load_op_gnt),
    .load_op_valid_i (load_op_valid),
    .load_op_i       (load_op),
    .load_op_addr_i  (load_op_addr),
    .load_op_strb_i  (load_op_strb),
    .load_id_i       (load_id)
  );

  vsu vsu (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    // Interface with `vinsn_launcher`
    .vfu_req_valid_i (vfu_req_valid),
    .vfu_req_ready_o (vfu_ready[VSU]),
    .target_vfu_i    (target_vfu),
    .vfu_req_i       (vfu_req),
    // Interface with `vrf_accesser`
    .store_op_valid_i(store_op_valid),
    .store_op_ready_o(store_op_ready),
    .store_op_i      (store_op),
    // Output store operands
    .store_op_ready_i(store_op_ready_i),
    .store_op_valid_o(store_op_valid_o),
    .store_op_o      (store_op_o),
    // Interface with committer
    .done_o          (vfu_done[VSU]),
    .done_insn_id_o  (vfu_done_id[VSU]),
    .insn_use_vd_o   (vfu_use_vd[VSU]),
    .insn_vd_o       (vfu_vd[VSU])
  );

  vlu vlu (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    // Interface with `vinsn_launcher`
    .vfu_req_valid_i(vfu_req_valid),
    .vfu_req_ready_o(vfu_ready[VLU]),
    .target_vfu_i   (target_vfu),
    .vfu_req_i      (vfu_req),
    // Interface with the scalar core
    .load_op_valid_i(load_op_valid_i),
    .load_op_ready_o(load_op_ready_o),
    .load_op_i      (load_op_i),
    // Interface with `vrf_accesser`
    // req/gnt nameing for accesser's generating vrf req iff valid signal is asserted.
    .load_op_gnt_i  (load_op_gnt),
    .load_op_valid_o(load_op_valid),
    .load_op_o      (load_op),
    .load_op_addr_o (load_op_addr),
    .load_op_strb_o (load_op_strb),
    .load_id_o      (load_id),
    // Interface with committer
    .done_o         (vfu_done[VLU]),
    .done_insn_id_o (vfu_done_id[VLU]),
    .insn_use_vd_o  (vfu_use_vd[VLU]),
    .insn_vd_o      (vfu_vd[VLU])
  );


endmodule : rvv_core
