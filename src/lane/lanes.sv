`include "core_pkg.svh"

module lanes
  import core_pkg::*;
#(

) (
  input  logic                      clk_i,
  input  logic                      rst_ni,
  input  logic      [InsnIDNum-1:0] insn_commit_i,
  // Interface between `vrf_accesser` and `vinsn_launcher`
  input  logic                      op_req_valid_i,
  output logic                      op_req_ready_o,
  input  op_req_t                   op_req_i,
  // Interface between `vfus` and `vinsn_launcher`
  input  logic                      vfu_req_valid_i,
  output logic                      vfu_req_ready_o,
  input  vfu_req_t                  vfu_req_i,
  input  vfu_e                      target_vfu_i,
  // Interface between `vfus` and `vinsn_launcher`
  output logic      [NrLaneVFU-1:0] vfus_done_o,
  output insn_id_t  [NrLaneVFU-1:0] vfus_done_id_o,
  // Output store operand
  input  logic      [   NrLane-1:0] store_op_ready_i,
  output logic      [   NrLane-1:0] store_op_valid_o,
  output vrf_data_t [   NrLane-1:0] store_op_o,
  // Input load value
  input  logic      [   NrLane-1:0] load_op_valid_i,
  output logic      [   NrLane-1:0] load_op_gnt_o,
  input  vrf_data_t [   NrLane-1:0] load_op_i,
  input  vrf_strb_t [   NrLane-1:0] load_op_strb_i,
  input  vrf_addr_t [   NrLane-1:0] load_op_addr_i,
  input  insn_id_t  [   NrLane-1:0] load_id_i
);
  logic op_req_valid;
  logic [NrLane-1:0] op_req_ready;
  logic vfu_req_valid;
  logic [NrLane-1:0] vfu_req_ready;

  logic [NrLane-1:0][NrLaneVFU-1:0] vfus_done;
  insn_id_t [NrLane-1:0][NrLaneVFU-1:0] vfus_done_id;

  // Synchronize signals of each lane
  always_comb begin
    op_req_ready_o  = &op_req_ready;
    op_req_valid    = op_req_valid_i & op_req_ready_o;
    vfu_req_ready_o = &vfu_req_ready;
    vfu_req_valid   = vfu_req_ready_o & vfu_req_valid_i;
    // TODO: done signals will be asserted for one cycle, can we ensure that
    // all of lanes will complete at the same time?
    vfus_done_id_o  = vfus_done_id[0];
    for (int unsigned i = 0; i < NrLaneVFU; ++i) vfus_done_o[i] = vfus_done[0];
  end

  for (genvar lane_id = 0; lane_id < NrLane; lane_id++) begin : gen_lane
    lane #(
      .LaneId(lane_id)
    ) lane (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .insn_commit_i   (insn_commit_i),
      // Interface between `vrf_accesser` and `vinsn_launcher`
      .op_req_valid_i  (op_req_valid),
      .op_req_ready_o  (op_req_ready[lane_id]),
      .op_req_i        (op_req_i),
      // Interface between `vfus` and `vinsn_launcher`
      .vfu_req_valid_i (vfu_req_valid),
      .vfu_req_ready_o (vfu_req_ready[lane_id]),
      .vfu_req_i       (vfu_req_i),
      .target_vfu_i    (target_vfu_i),
      // Interface between `vfus` and `vinsn_launcher`
      .vfus_done_o     (vfus_done[lane_id]),
      .vfus_done_id_o  (vfus_done_id[lane_id]),
      // Output store operand
      .store_op_ready_i(store_op_ready_i[lane_id]),
      .store_op_valid_o(store_op_valid_o[lane_id]),
      .store_op_o      (store_op_o[lane_id]),
      // Input load value
      .load_op_valid_i (load_op_valid_i[lane_id]),
      .load_op_gnt_o   (load_op_gnt_o[lane_id]),
      .load_op_i       (load_op_i[lane_id]),
      .load_op_strb_i  (load_op_strb_i[lane_id]),
      .load_op_addr_i  (load_op_addr_i[lane_id]),
      .load_id_i       (load_id_i[lane_id])
    );
  end : gen_lane

endmodule : lanes
