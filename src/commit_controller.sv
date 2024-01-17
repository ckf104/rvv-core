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
  // commit control signals used by `vrf_accesser`
  input  logic                     insn_can_commit_i,
  input  insn_id_t                 insn_can_commit_id_i,
  output logic     [InsnIDNum-1:0] insn_can_commit_o
);
  logic [InsnIDNum-1:0] insn_done_d, insn_done_q;
  logic no_commit_insn;
  insn_id_t commit_id;

  lzc #(
    .WIDTH(InsnIDNum),
    .MODE (0)           // count trailing zero
  ) lzc (
    .in_i   (insn_done_q),
    .cnt_o  (commit_id),
    .empty_o(no_commit_insn)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      insn_done_q <= 'b0;
    end else begin
      insn_done_q <= insn_done_d;
    end
  end

  always_comb begin : insn_done
    insn_done_d = insn_done_q;
    for (int unsigned i = 0; i < NrVFU; ++i) begin
      insn_done_d[vfu_done_id_i[i]] |= vfu_done_i[i];
    end
    // If we have committable instruction without illegal instruction exception,
    // the instruction with the lowest id will be committed.
    if (!illegal_insn_i && !no_commit_insn) insn_done_d[commit_id] = 1'b0;
  end : insn_done

  logic [InsnIDNum-1:0] insn_can_commit_d, insn_can_commit_q;
  assign insn_can_commit_o = insn_can_commit_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      insn_can_commit_q <= 'b0;
    end else begin
      insn_can_commit_q <= insn_can_commit_d;
    end
  end

  always_comb begin : insn_can_commit
    insn_can_commit_d = insn_can_commit_q;
    if (insn_can_commit_i) begin
      insn_can_commit_d[insn_can_commit_id_i] = 1'b1;
    end
    if (illegal_insn_i) insn_can_commit_d[insn_id_i] = 1'b0;
    else if (!no_commit_insn) insn_can_commit_d[commit_id] = 1'b0;
  end : insn_can_commit

  always_comb begin : send_done_signal
    done_o         = 1'b0;
    illegal_insn_o = 1'b0;
    done_insn_id_o = insn_id_i;

    if (illegal_insn_i) begin
      done_o         = 1'b1;
      illegal_insn_o = 1'b1;
    end else if (!no_commit_insn) begin
      done_o         = 1'b1;
      done_insn_id_o = commit_id;
    end
  end

endmodule : commit_controller
