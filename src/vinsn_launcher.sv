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
  input  logic       [    NrVFU-1:0] vfu_done_i,
  input  insn_id_t   [    NrVFU-1:0] vfu_done_id_i,
  output logic       [    NrVFU-1:0] vfu_done_gnt_o,
  // commit control signals used by `vrf_accesser`
  input  logic                       insn_can_commit_i,
  input  insn_id_t                   insn_can_commit_id_i,
  output logic       [InsnIDNum-1:0] insn_can_commit_o
);
  // `vinsn_launcher` will send `vfu_req` to `valu_wrapper` and
  // `op_req` to `vrf_accesser`, use a mask to ensure that both
  // req are sent once and only once.
  logic vfu_req_mask_q, vfu_req_mask_d;
  vfu_req_t vfu_req_q, vfu_req_d;
  vfu_e target_vfu_q, target_vfu_d, target_vfu;
  logic vfu_req_valid_q, vfu_req_valid_d;

  logic op_req_mask_q, op_req_mask_d;
  op_req_t op_req_q, op_req_d;
  logic op_req_valid_q, op_req_valid_d;

  logic last_flip_bit_q, last_flip_bit_d;

  assign vfu_req_valid_o = vfu_req_valid_q;
  assign vfu_req_o       = vfu_req_q;
  assign op_req_valid_o  = op_req_valid_q;
  assign op_req_o        = op_req_q;
  assign target_vfu_o    = target_vfu_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vfu_req_mask_q  <= 1'b0;
      op_req_mask_q   <= 1'b0;
      // Opposite initial value compared with `flip_bit_q` in `vinsn_decoder`
      last_flip_bit_q <= 1'b1;
    end else begin
      vfu_req_mask_q  <= vfu_req_mask_d;
      op_req_mask_q   <= op_req_mask_d;
      last_flip_bit_q <= last_flip_bit_d;
    end
  end


  always_comb begin
    vfu_req_mask_d  = vfu_req_mask_q;
    op_req_mask_d   = op_req_mask_q;
    last_flip_bit_d = last_flip_bit_q;

    target_vfu      = GetVFUByVOp(issue_req_i.vop);


    if (vfu_req_valid_o && vfu_req_ready_i[target_vfu_o]) vfu_req_mask_d = 1'b0;
    if (op_req_valid_o && op_req_ready_i) op_req_mask_d = 1'b0;
    if (issue_req_valid_i && issue_req_i.flip_bit != last_flip_bit_q) begin
      vfu_req_mask_d  = 1'b1;
      op_req_mask_d   = 1'b1;
      last_flip_bit_d = issue_req_i.flip_bit;
    end
    issue_req_ready_o = 1'b0;
    if ((!vfu_req_mask_d || vfu_req_ready_i[target_vfu_o]) && (!op_req_mask_d || op_req_ready_i)) begin
      issue_req_ready_o = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // don't need to reset `vfu_req_q` and `op_req_q`, `target_vfu_q`
      vfu_req_valid_q <= 1'b0;
      op_req_valid_q  <= 1'b0;
    end else begin
      vfu_req_valid_q <= vfu_req_valid_d;
      op_req_valid_q  <= op_req_valid_d;
      vfu_req_q       <= vfu_req_d;
      target_vfu_q    <= target_vfu_d;
      op_req_q        <= op_req_d;
    end
  end

  always_comb begin
    // Deassert valid signal once handshake is successful.
    vfu_req_valid_d = vfu_req_valid_q;
    vfu_req_d       = vfu_req_q;
    target_vfu_d    = target_vfu_q;
    if (vfu_req_ready_i[target_vfu] || !vfu_req_valid_q) begin
      vfu_req_valid_d     = issue_req_valid_i & vfu_req_mask_d;

      vfu_req_d.vop       = issue_req_i.vop;
      vfu_req_d.vew       = issue_req_i.vew;
      vfu_req_d.vlB       = issue_req_i.vlB;
      vfu_req_d.use_vs    = issue_req_i.use_vs;
      vfu_req_d.waddr     = GetVRFAddr(issue_req_i.vd);
      vfu_req_d.scalar_op = issue_req_i.scalar_op;
      vfu_req_d.insn_id   = issue_req_i.insn_id;
      target_vfu_d        = target_vfu;
    end

    op_req_valid_d = op_req_valid_q;
    op_req_d       = op_req_q;
    if (op_req_ready_i || !op_req_valid_q) begin
      op_req_valid_d     = issue_req_valid_i & op_req_mask_d;

      op_req_d.vs1       = issue_req_i.vs1;
      op_req_d.vs2       = issue_req_i.vs2;
      op_req_d.queue_req = GetOpQueue(issue_req_i.vop, issue_req_i.use_vs);
      op_req_d.vlB       = issue_req_i.vlB;
    end

  end

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
    .vfu_done_gnt_o      (vfu_done_gnt_o),
    // commit control signals used by `vrf_accesser`
    .insn_can_commit_i   (insn_can_commit_i),
    .insn_can_commit_id_i(insn_can_commit_id_i),
    .insn_can_commit_o   (insn_can_commit_o)
  );



endmodule : vinsn_launcher
