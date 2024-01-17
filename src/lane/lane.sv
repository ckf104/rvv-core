`include "core_pkg.svh"

module lane
  import core_pkg::*;
#(
  parameter int unsigned LaneId = 0
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
  input  logic                      store_op_ready_i,
  output logic                      store_op_valid_o,
  output vrf_data_t                 store_op_o,
  // Input load value
  input  logic                      load_op_valid_i,
  output logic                      load_op_gnt_o,
  input  vrf_data_t                 load_op_i,
  input  vrf_strb_t                 load_op_strb_i,
  input  vrf_addr_t                 load_op_addr_i,
  input  insn_id_t                  load_id_i
);
  vrf_data_t [NrWriteBackVFU-1:0] vfu_result_wdata;
  vrf_strb_t [NrWriteBackVFU-1:0] vfu_result_wstrb;
  vrf_addr_t [NrWriteBackVFU-1:0] vfu_result_addr;
  insn_id_t  [NrWriteBackVFU-1:0] vfu_result_id;
  logic      [NrWriteBackVFU-1:0] vfu_result_valid;
  logic      [NrWriteBackVFU-1:0] vfu_result_gnt;

  assign vfu_result_wdata[WB_VLU] = load_op_i;
  assign vfu_result_wstrb[WB_VLU] = load_op_strb_i;
  assign vfu_result_addr[WB_VLU]  = load_op_addr_i;
  assign vfu_result_valid[WB_VLU] = load_op_valid_i;
  assign vfu_result_id[WB_VLU]    = load_id_i;
  assign load_op_gnt_o            = vfu_result_gnt[WB_VLU];

  logic      [NrOpQueue-1:0] op_ready;
  logic      [NrOpQueue-1:0] op_valid;
  vrf_data_t [NrOpQueue-1:0] operand;

  assign store_op_valid_o  = op_valid[StoreOp];
  assign store_op_o        = operand[StoreOp];
  assign op_ready[StoreOp] = store_op_ready_i;

  vrf_accesser #(
    .LaneId(LaneId)
  ) accesser (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    // interface with `vinsn_launcher`
    .req_valid_i       (op_req_valid_i),
    .req_ready_o       (op_req_ready_o),
    .op_req_i          (op_req_i),
    .insn_commit_i     (insn_commit_i),
    // interface with `vfus`
    .vfu_result_wdata_i(vfu_result_wdata),
    .vfu_result_wstrb_i(vfu_result_wstrb),
    .vfu_result_addr_i (vfu_result_addr),
    .vfu_result_id_i   (vfu_result_id),
    .vfu_result_valid_i(vfu_result_valid),
    .vfu_result_gnt_o  (vfu_result_gnt),
    // output operands
    .op_ready_i        (op_ready),
    .op_valid_o        (op_valid),
    .operand_o         (operand)
  );

  /*logic [NrVFU-1:0][InsnIDNum-1:0] vfus_done;
  logic [InsnIDNum-1:0][NrVFU-1:0] vfus_done_trans;
  always_comb begin
    for (int i = 0; i < NrVFU; ++i) begin
      for (int j = 0; j < InsnIDNum; ++j) begin
        vfus_done_trans[j][i] = vfus_done[i][j];
      end
    end
    for (int i = 0; i < InsnIDNum; ++i) begin
      vfus_done_o[i] = |vfus_done_trans[i];
    end
  end*/

  valu_wrapper #(
    .LaneId(LaneId)
  ) alu_wrapper (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    // interface with `vinsn_launcher`
    .vfu_req_valid_i   (vfu_req_valid_i),
    .vfu_req_ready_o   (vfu_req_ready_o),
    .vfu_req_i         (vfu_req_i),
    .target_vfu_i      (target_vfu_i),
    // interface with `vinsn_launcher`
    .alu_done_o        (vfus_done_o[VALU]),
    .alu_done_id_o     (vfus_done_id_o[VALU]),
    // interface with `vrf_accesser`
    .op_valid_i        (op_valid[ALUB:ALUA]),
    .op_ready_o        (op_ready[ALUB:ALUA]),
    .alu_op_i          (operand[ALUB:ALUA]),
    // interface with `vrf_accesser`
    .alu_result_wdata_o(vfu_result_wdata[WB_VALU]),
    .alu_result_wstrb_o(vfu_result_wstrb[WB_VALU]),
    .alu_result_addr_o (vfu_result_addr[WB_VALU]),
    .alu_result_id_o   (vfu_result_id[WB_VALU]),
    .alu_result_valid_o(vfu_result_valid[WB_VALU]),
    .alu_result_gnt_i  (vfu_result_gnt[WB_VALU])
  );

endmodule : lane
