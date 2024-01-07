`include "core_pkg.svh"

module commit_controller
  import core_pkg::*;
#(

) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  insn_id_t                 insn_id_i,
  // Note: `illegal_insn_o` depends on `valid_insn_i` combinationally.
  // It will be output by decoder in the same cycle.
  input  logic                     illegal_insn_i,
  output logic                     done_o,
  output insn_id_t                 done_insn_id_o,
  output logic                     illegal_insn_o,
  // interface with `vfus`
  input  logic     [    NrVFU-1:0] vfu_done_i,
  input  insn_id_t [    NrVFU-1:0] vfu_done_id_i,
  output logic     [    NrVFU-1:0] vfu_done_gnt_o,
  // commit control signals used by `vrf_accesser`
  input  logic                     insn_can_commit_i,
  input  insn_id_t                 insn_can_commit_id_i,
  output logic     [InsnIDNum-1:0] insn_can_commit_o
);
  logic arbit_vfu_done;
  insn_id_t arbit_vfu_done_id;

  rr_arb_tree #(
    .NumIn    (NrVFU),
    .DataWidth($bits(insn_id_t)),
    .AxiVldRdy(1'b0)
  ) bank_req_arbiter (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .flush_i(1'b0),
    .rr_i   ('0),
    .data_i (vfu_done_id_i),
    .req_i  (vfu_done_i),
    .gnt_o  (vfu_done_gnt_o),
    .data_o (arbit_vfu_done_id),
    .idx_o  (),
    .req_o  (arbit_vfu_done),
    .gnt_i  (~illegal_insn_i)
  );

  logic [InsnIDNum-1:0] insn_can_commit_d, insn_can_commit_q;
  assign insn_can_commit_o = insn_can_commit_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      insn_can_commit_q <= 'b0;
    end else begin
      insn_can_commit_q <= insn_can_commit_d;
    end
  end

  always_comb begin
    insn_can_commit_d = insn_can_commit_q;
    if (insn_can_commit_i) begin
      insn_can_commit_d[insn_can_commit_id_i] = 1'b1;
    end

    done_o         = 1'b0;
    illegal_insn_o = 1'b0;
    done_insn_id_o = insn_id_i;

    if (illegal_insn_i) begin
      done_o                       = 1'b1;
      illegal_insn_o               = 1'b1;
      insn_can_commit_d[insn_id_i] = 1'b0;
    end else if (arbit_vfu_done) begin
      done_o                               = 1'b1;
      done_insn_id_o                       = arbit_vfu_done_id;
      // Clear `insn_can_commit` value if the instruction is done
      insn_can_commit_d[arbit_vfu_done_id] = 1'b0;
    end
  end

endmodule : commit_controller
