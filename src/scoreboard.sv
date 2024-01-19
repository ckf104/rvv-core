`include "core_pkg.svh"
`include "rvv_pkg.svh"

module scoreboard
  import core_pkg::*;
  import rvv_pkg::*;
#(
  parameter ReaderCounterWidth = 2
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,
  input  issue_req_t                 issue_req_i,
  // `issue_req_i` indicates that `issue_req_i` has been issued by launcher
  // successfully. Scoreboard updates `reading_q`, `writing_q` after instruction
  // has been issued to avoid fake `stall` signal.
  input  logic                       is_issued_i,
  input  logic       [NrOpQueue-1:0] op_access_done_i,
  input  vreg_t      [NrOpQueue-1:0] op_access_vs_i,
  input  logic       [    NrVFU-1:0] insn_done_i,
  input  logic       [    NrVFU-1:0] insn_use_vd_i,
  input  vreg_t      [    NrVFU-1:0] insn_vd_i,
  input  insn_id_t   [    NrVFU-1:0] insn_done_id_i,
  output logic                       stall
);
  // Currently `vinsn_running_q` is only used for debug purpose.
  logic [InsnIDNum-1:0] vinsn_running_d, vinsn_running_q;

  always_comb begin : comp_running_vinsn
    vinsn_running_d = vinsn_running_q;
    if (is_issued_i) vinsn_running_d[issue_req_i.insn_id] = 1'b1;
    for (int unsigned i = 0; i < NrVFU; ++i) begin
      if (insn_done_i[i]) vinsn_running_d[insn_done_id_i[i]] = 1'b0;
    end
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vinsn_running_q <= 'b0;
    end else begin
      vinsn_running_q <= vinsn_running_d;
    end
  end

  logic [NrVReg-1:0] writing_d, writing_q;
  // insn_id_t [NrVReg-1:0] writing_id_d, writing_id_q;

  // allow 2^ReaderCounterWidth - 1 instructions reading the same reg
  logic [NrVReg-1:0][ReaderCounterWidth-1:0] reading_d, reading_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Don't need to reset writing_id_q
      writing_q <= 'b0;
      reading_q <= 'b0;
    end else begin
      writing_q <= writing_d;
      reading_q <= reading_d;
    end
  end

  always_comb begin : update_writing
    writing_d = writing_q;
    // writing_id_d = writing_id_q;

    for (int unsigned i = 0; i < NrVFU; ++i) begin
      if (insn_use_vd_i[i] && insn_done_i[i]) begin
        writing_d[insn_vd_i[i]] = 1'b0;
        // writing_id_d[insn_vd_i[i]] = issue_req_i.insn_id;
      end
    end
    if (is_issued_i) begin
      if (issue_req_i.use_vs[VD]) begin
        writing_d[issue_req_i.vs[VD]] = 1'b1;
        // writing_id_d[issue_req_i.vd] = issue_req_i.insn_id;
      end
    end
  end : update_writing

  always_comb begin : update_reading
    reading_d = reading_q;
    for (int unsigned i = 0; i < NrOpQueue; ++i) begin
      if (op_access_done_i[i]) begin
        reading_d[op_access_vs_i[i]] -= 1;
      end
    end
    if (is_issued_i) begin
      if (issue_req_i.use_vs[VS1]) begin
        reading_d[issue_req_i.vs[VS1]] += 1;
      end
      if (issue_req_i.use_vs[VS2]) begin
        reading_d[issue_req_i.vs[VS2]] += 1;
      end
    end
  end : update_reading

  always_comb begin : gen_stall
    stall = 1'b0;
    // We don't care about validity of `issue_req_i`. If it's not valid,
    // decoder can decode an instruction anyway despite asserted `stall` signal.
    // `writing_d` depends on `issue_req_ready_o`, which depends on `stall`,
    // therefore using `writing_d` here will cause combinational loop.
    if (issue_req_i.use_vs[VD] && writing_q[issue_req_i.vs[VD]]) stall = 1'b1;  //WAW
    else if (issue_req_i.use_vs[VD] && |reading_q[issue_req_i.vs[VD]]) stall = 1'b1;  // WAR
    else if (issue_req_i.use_vs[VS1] && writing_q[issue_req_i.vs[VS1]]) stall = 1'b1;  // RAW
    else if (issue_req_i.use_vs[VS2] && writing_q[issue_req_i.vs[VS2]]) stall = 1'b1;  // RAW
  end : gen_stall

endmodule : scoreboard
