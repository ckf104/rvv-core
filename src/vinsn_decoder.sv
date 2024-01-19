`include "rvv_pkg.svh"
`include "core_pkg.svh"

module vinsn_decoder
  import rvv_pkg::*;
  import core_pkg::*;
#(

) (
  // input  logic                clk_i,
  // input  logic                rst_ni,
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

  logic illegal_insn;
  varith_type_t varith_insn;
  vmem_type_t vmem_insn;

  vew_e store_vew, load_vew;
  always_comb begin : decode_store_vew

  end

  assign ready_o        = req_ready_i;
  assign illegal_insn_o = valid_i && illegal_insn;
  assign varith_insn    = insn_i;
  assign vmem_insn      = insn_i;

  always_comb begin
    issue_req_o          = 'b0;  // default zero
    store_vew            = EW8;  // default zero
    load_vew             = EW8;  // default zero
    illegal_insn         = 1'b0;

    issue_req_o.vew[VS1] = vec_context_i.vtype.vsew;
    issue_req_o.vew[VS2] = vec_context_i.vtype.vsew;
    issue_req_o.vew[VD]  = vec_context_i.vtype.vsew;
    issue_req_o.insn_id  = insn_id_i;
    issue_req_o.vl       = vec_context_i.vl;
    issue_req_o.vstart   = vec_context_i.vstart;
    unique case (varith_insn.opcode)
      OpcodeVec: begin
        issue_req_o.vs[VS1]    = varith_insn.vs1;
        issue_req_o.vs[VS2]    = varith_insn.vs2;
        issue_req_o.vs[VD]     = varith_insn.vd;
        issue_req_o.use_vs[VD] = 1'b1;
        if (varith_insn.vm == Masked) illegal_insn = 1'b1;
        unique case (varith_insn.func3)
          OPIVV: begin
            issue_req_o.use_vs[VS2:VS1] = 2'b11;
            unique case (varith_insn.func6)
              OPVADD:  issue_req_o.vop = VADD;
              OPVSUB:  issue_req_o.vop = VSUB;
              OPVSLL:  issue_req_o.vop = VSLL;
              OPVSRL:  issue_req_o.vop = VSRL;
              OPVSRA:  issue_req_o.vop = VSRA;
              OPVMERGE: begin
                issue_req_o.use_vs[VS2] = varith_insn.vm == Masked;
                issue_req_o.vop         = VMERGE;
              end
              default: illegal_insn = 1'b1;
            endcase
          end
          OPIVI: begin
            issue_req_o.use_vs[VS2:VS1] = 2'b10;
            issue_req_o.scalar_op       = {{SignExtW{varith_insn.vs1[19]}}, varith_insn.vs1};
            unique case (varith_insn.func6)
              OPVADD:  issue_req_o.vop = VADD;
              OPVSUB:  issue_req_o.vop = VSUB;
              OPVSLL:  issue_req_o.vop = VSLL;
              OPVSRL:  issue_req_o.vop = VSRL;
              OPVSRA:  issue_req_o.vop = VSRA;
              OPVMERGE: begin
                issue_req_o.use_vs[VS2] = varith_insn.vm == Masked;
                issue_req_o.vop         = VMERGE;
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
        issue_req_o.vs[VS1]         = vmem_insn.vs3;  // vs3 is encoded in the same position as rd
        issue_req_o.use_vs[VS2:VS1] = 2'b01;
        issue_req_o.use_vs[VD]      = 1'b0;
        issue_req_o.vop             = VSE;
        issue_req_o.vew             = {3{store_vew}};
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
        issue_req_o.vs[VD]          = vmem_insn.vs3;  // vs3 is encoded in the same position as rd
        issue_req_o.use_vs[VS2:VS1] = 2'b00;
        issue_req_o.use_vs[VD]      = 1'b1;
        issue_req_o.vop             = VLE;
        issue_req_o.vew             = {3{load_vew}};
      end
      default: illegal_insn = 1'b1;
    endcase

    req_valid_o = !illegal_insn && valid_i;
  end

endmodule : vinsn_decoder
