`include "rvv_pkg.svh"
`include "core_pkg.svh"

module vinsn_decoder
  import rvv_pkg::*;
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
  // Interface with `vinsn_launcher`
  input  logic                req_ready_i,
  output logic                req_valid_o,
  output issue_req_t          issue_req_o,
  // `illegal_insn_o` will be output in the same cycle.
  output logic                illegal_insn_o
);

  localparam int unsigned SignExtW = $bits(vrf_data_t) - $bits(vreg_t);

  logic flip_bit_q, flip_bit_d;
  logic req_valid_d, req_valid_q;
  logic illegal_insn;
  issue_req_t issue_req_d, issue_req_q;
  varith_type_t varith_insn;
  vmem_type_t   vmem_insn;

  vew_e store_vew, load_vew;
  always_comb begin : decode_store_vew

  end

  assign req_valid_o    = req_valid_q;
  assign ready_o        = req_ready_i || !req_valid_o;
  assign illegal_insn_o = valid_i && ready_o && illegal_insn;
  assign issue_req_o    = issue_req_q;
  assign varith_insn    = insn_i;
  assign vmem_insn      = insn_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // don't need to reset `issue_req_q`
      req_valid_q <= 'b0;
      flip_bit_q  <= 'b0;
    end else begin
      req_valid_q <= req_valid_d;
      issue_req_q <= issue_req_d;
      flip_bit_q  <= flip_bit_d;
    end
  end

  always_comb begin
    flip_bit_d   = flip_bit_q;
    issue_req_d  = issue_req_q;
    store_vew    = EW8;
    load_vew     = EW8;
    illegal_insn = 1'b0;
    if (req_ready_i || !req_valid_q) begin
      issue_req_d.vew     = vec_context_i.vtype.vsew;
      issue_req_d.insn_id = insn_id_i;
      unique case (varith_insn.opcode)
        OpcodeVec: begin
          issue_req_d.vs1    = varith_insn.vs1;
          issue_req_d.vs2    = varith_insn.vs2;
          issue_req_d.vd     = varith_insn.vd;
          issue_req_d.use_vd = 1'b1;
          issue_req_d.vlB    = vec_context_i.vle << vec_context_i.vtype.vsew;
          if (varith_insn.vm == Masked) illegal_insn = 1'b1;
          unique case (varith_insn.func3)
            OPIVV: begin
              issue_req_d.use_vs = 2'b11;
              unique case (varith_insn.func6)
                OPVADD:  issue_req_d.vop = VADD;
                OPVSUB:  issue_req_d.vop = VSUB;
                OPVSLL:  issue_req_d.vop = VSLL;
                OPVSRL:  issue_req_d.vop = VSRL;
                OPVSRA:  issue_req_d.vop = VSRA;
                OPVMERGE: begin
                  issue_req_d.use_vs[1] = varith_insn.vm == Masked;
                  issue_req_d.vop       = VMERGE;
                end
                default: illegal_insn = 1'b1;
              endcase
            end
            OPIVI: begin
              issue_req_d.use_vs    = 2'b10;
              issue_req_d.scalar_op = {{SignExtW{varith_insn.vs1[19]}}, varith_insn.vs1};
              unique case (varith_insn.func6)
                OPVADD:  issue_req_d.vop = VADD;
                OPVSUB:  issue_req_d.vop = VSUB;
                OPVSLL:  issue_req_d.vop = VSLL;
                OPVSRL:  issue_req_d.vop = VSRL;
                OPVSRA:  issue_req_d.vop = VSRA;
                OPVMERGE: begin
                  issue_req_d.use_vs[1] = varith_insn.vm == Masked;
                  issue_req_d.vop       = VMERGE;
                end
                default: illegal_insn = 1'b1;
              endcase
            end
            default: illegal_insn = 1'b1;
          endcase

        end
        // TODO: support complete decoding for store instruction
        OpcodeStoreFP: begin
          // verilog_format: off
          unique case ({vmem_insn.mew, vmem_insn.width})
            4'b0000: store_vew = EW8;
            4'b0101: store_vew = EW16;
            4'b0110: store_vew = EW32;
            4'b0111: store_vew = EW64;
            default: illegal_insn = 1'b1;
          endcase
          // verilog_format: on
          issue_req_d.vs1    = vmem_insn.vs3;  // vs3 is encoded in the same position as rd
          issue_req_d.use_vs = 2'b01;
          issue_req_d.vop    = VSE;
          issue_req_d.vlB    = vec_context_i.vle << store_vew;
          issue_req_d.vew    = store_vew;
          issue_req_d.use_vd = 1'b0;
        end
        OpcodeLoadFP: begin
          // verilog_format: off
          unique case ({vmem_insn.mew, vmem_insn.width})
            4'b0000: load_vew = EW8;
            4'b0101: load_vew = EW16;
            4'b0110: load_vew = EW32;
            4'b0111: load_vew = EW64;
            default: illegal_insn = 1'b1;
          endcase
          // verilog_format: on
          issue_req_d.vd     = vmem_insn.vs3;  // vs3 is encoded in the same position as rd
          issue_req_d.use_vs = 2'b00;
          issue_req_d.vop    = VLE;
          issue_req_d.vlB    = vec_context_i.vle << load_vew;
          issue_req_d.vew    = load_vew;
          issue_req_d.use_vd = 1'b1;
        end
        default: illegal_insn = 1'b1;
      endcase

      req_valid_d = !illegal_insn && valid_i;
      if (req_valid_d) begin
        issue_req_d.flip_bit = flip_bit_q;
        flip_bit_d           = ~flip_bit_q;
      end
    end else begin
      req_valid_d = req_valid_q;
    end
  end

endmodule : vinsn_decoder
