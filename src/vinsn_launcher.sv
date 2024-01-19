`include "core_pkg.svh"

module vinsn_launcher
  import core_pkg::*;
#(
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,
  // Interface with `vinsn_decoder`
  input  logic                       issue_req_valid_i,
  output logic                       issue_req_ready_o,
  input  issue_req_t                 issue_req_i,
  // Interface with `valu_wrapper`
  input  logic       [    NrVFU-1:0] vfu_req_ready_i,
  output logic                       vfu_req_valid_o,
  output vfu_e                       target_vfu_o,
  output vfu_req_t                   vfu_req_o,
  // Interface with `vrf_accesser`
  input  logic                       op_req_ready_i,
  output logic                       op_req_valid_o,
  output op_req_t                    op_req_o,
  // Commit controller
  input  insn_id_t                   insn_id_i,
  // Note: `illegal_insn_o` depends on `valid_insn_i` combinationally.
  // It will be output by decoder in the same cycle.
  input  logic                       illegal_insn_i,
  output logic                       done_o,
  output insn_id_t                   done_insn_id_o,
  output logic                       illegal_insn_o,
  // done signals from vfus and `vrf_accessser`
  input  logic       [    NrVFU-1:0] vfu_done_i,
  input  insn_id_t   [    NrVFU-1:0] vfu_done_id_i,
  input  logic       [    NrVFU-1:0] vfu_use_vd_i,
  input  vreg_t      [    NrVFU-1:0] vfu_vd_i,
  input  logic       [NrOpQueue-1:0] op_access_done_i,
  input  vreg_t      [NrOpQueue-1:0] op_access_vs_i,
  // commit control signals used by `vrf_accesser`
  input  logic                       insn_can_commit_i,
  input  insn_id_t                   insn_can_commit_id_i,
  output logic       [InsnIDNum-1:0] insn_can_commit_o
);
  issue_req_t issue_req_d, issue_req_q;
  logic issue_req_valid_d, issue_req_valid_q;

  // `vinsn_launcher` will send `vfu_req` to `valu_wrapper` and
  // `op_req` to `vrf_accesser`, use a mask to ensure that both
  // req are sent once and only once.
  logic vfu_req_mask_q, vfu_req_mask_d;
  logic op_req_mask_q, op_req_mask_d;

  always_comb begin : issue_req_logic
    issue_req_d       = issue_req_q;
    issue_req_valid_d = issue_req_valid_q;
    issue_req_ready_o = 1'b0;
    if (((vfu_req_ready_i[target_vfu_o] && vfu_req_valid_o) || !vfu_req_mask_q) &&
        ((op_req_ready_i && op_req_valid_o) || !op_req_mask_q)) begin
      issue_req_d       = issue_req_i;
      issue_req_valid_d = issue_req_valid_i;
      issue_req_ready_o = 1'b1;
    end
  end

  always_comb begin : mask_logic
    vfu_req_mask_d = vfu_req_mask_q;
    op_req_mask_d  = op_req_mask_q;

    if (vfu_req_valid_o && vfu_req_ready_i[target_vfu_o]) vfu_req_mask_d = 1'b0;
    if (op_req_valid_o && op_req_ready_i) op_req_mask_d = 1'b0;
    if (issue_req_ready_o && issue_req_valid_i) begin
      vfu_req_mask_d = 1'b1;
      op_req_mask_d  = 1'b1;
    end
  end
  // A single cycle pulse to show that a new instruction is issued.
  logic issue_new_insn;
  assign issue_new_insn = issue_req_ready_o && (op_req_mask_q || vfu_req_mask_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_req_valid_q <= 'b0;
    end else begin
      issue_req_q       <= issue_req_d;
      issue_req_valid_q <= issue_req_valid_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vfu_req_mask_q <= 1'b0;
      op_req_mask_q  <= 1'b0;
    end else begin
      vfu_req_mask_q <= vfu_req_mask_d;
      op_req_mask_q  <= op_req_mask_d;
    end
  end

  logic stall;  // Stall due to hazard.

  scoreboard scoreboard (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .issue_req_i     (issue_req_q),
    .is_issued_i     (issue_new_insn),
    .op_access_done_i(op_access_done_i),
    .op_access_vs_i  (op_access_vs_i),
    .insn_done_i     (vfu_done_i),
    .insn_use_vd_i   (vfu_use_vd_i),
    .insn_vd_i       (vfu_vd_i),
    .insn_done_id_i  (vfu_done_id_i),
    .stall           (stall)
  );

  always_comb begin : gen_vfu_req
    // Deassert valid signal once handshake is successful.
    vfu_req_valid_o     = issue_req_valid_q & vfu_req_mask_q & ~stall;

    vfu_req_o.vop       = issue_req_q.vop;
    vfu_req_o.vew_vd    = issue_req_q.vew[VD];
    vfu_req_o.vl        = issue_req_q.vl;
    vfu_req_o.use_vs    = issue_req_q.use_vs;
    vfu_req_o.scalar_op = issue_req_q.scalar_op;
    vfu_req_o.insn_id   = issue_req_q.insn_id;
    vfu_req_o.vd        = issue_req_q.vs[VD];
    vfu_req_o.vstart    = issue_req_q.vstart;
    target_vfu_o        = GetVFUByVOp(issue_req_q.vop);

  end : gen_vfu_req

  // We always round vl up to multiple of ByteBlock, which
  // ensures that workloads of each lane are the same. But
  // vfu will receive real vl to generate appropriate mask
  //logic need_round;
  //assign need_round = issue_req_q.vlB[ByteBlockWidth-1:0] != 'b0;

  always_comb begin : gen_op_req
    op_req_valid_o     = issue_req_valid_q & op_req_mask_q & ~stall;

    op_req_o.vs        = issue_req_q.vs;
    op_req_o.vew       = issue_req_q.vew;
    op_req_o.queue_req = GetOpQueue(issue_req_q.vop, issue_req_q.use_vs);
    op_req_o.vl        = issue_req_q.vl;
    op_req_o.vstart    = issue_req_q.vstart;
`ifdef DUMP_VRF_ACCESS
    op_req_o.insn_id = issue_req_q.insn_id;
`endif
  end : gen_op_req

  // TODO: fix valid/ready bugs

  commit_controller controller (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .insn_id_i           (insn_id_i),
    // Note: `illegal_insn_o` depends on `valid_insn_i` combinationally.
    // It will be output by decoder in the same cycle.
    .illegal_insn_i      (illegal_insn_i),
    .done_o              (done_o),
    .done_insn_id_o      (done_insn_id_o),
    .illegal_insn_o      (illegal_insn_o),
    // interface with `vfus`
    .vfu_done_i          (vfu_done_i),
    .vfu_done_id_i       (vfu_done_id_i),
    // commit control signals used by `vrf_accesser`
    .insn_can_commit_i   (insn_can_commit_i),
    .insn_can_commit_id_i(insn_can_commit_id_i),
    .insn_can_commit_o   (insn_can_commit_o)
  );



endmodule : vinsn_launcher
