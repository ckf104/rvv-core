`include "core_pkg.svh"
`include "rvv_pkg.svh"

// `valu` should only contain combinational logic
module valu
  import core_pkg::*;
  import rvv_pkg::*;
#(

) (
  input  vrf_data_t [1:0] operand_i,
  input  vew_e            vew_i,
  input  vop_e            op_i,
  output vrf_data_t       result_o
);

  // Currently we have assumed that $bits(vrf_data_t) == 64
  typedef union packed {
    logic [0:0][63:0] w64;
    logic [1:0][31:0] w32;
    logic [3:0][15:0] w16;
    logic [7:0][7:0]  w8;
  } alu_operand_t;

  // alu_op[0] -> vs1, alu_op[1] -> vs2
  alu_operand_t [1:0] alu_operand;
  alu_operand_t result;

  assign result_o       = result;
  assign alu_operand[0] = operand_i[0];
  assign alu_operand[1] = operand_i[1];

  always_comb begin
    unique case (op_i)
      VADD:
      unique case (vew_i)
        EW64: for (int i = 0; i < 1; ++i) result.w64[i] = alu_operand[0].w64[i] + alu_operand[1].w64[i];
        EW32: for (int i = 0; i < 2; ++i) result.w32[i] = alu_operand[0].w32[i] + alu_operand[1].w32[i];
        EW16: for (int i = 0; i < 4; ++i) result.w16[i] = alu_operand[0].w16[i] + alu_operand[1].w16[i];
        EW8:  for (int i = 0; i < 8; ++i) result.w8[i] = alu_operand[0].w8[i] + alu_operand[1].w8[i];
      endcase
      VSUB:
      unique case (vew_i)
        EW64: for (int i = 0; i < 1; ++i) result.w64[i] = alu_operand[0].w64[i] - alu_operand[1].w64[i];
        EW32: for (int i = 0; i < 2; ++i) result.w32[i] = alu_operand[0].w32[i] - alu_operand[1].w32[i];
        EW16: for (int i = 0; i < 4; ++i) result.w16[i] = alu_operand[0].w16[i] - alu_operand[1].w16[i];
        EW8:  for (int i = 0; i < 8; ++i) result.w8[i] = alu_operand[0].w8[i] - alu_operand[1].w8[i];
      endcase
      VSLL:
      unique case (vew_i)
        EW64: for (int i = 0; i < 1; ++i) result.w64[i] = alu_operand[1].w64[i] << alu_operand[0].w64[i];
        EW32: for (int i = 0; i < 2; ++i) result.w32[i] = alu_operand[1].w32[i] << alu_operand[0].w32[i];
        EW16: for (int i = 0; i < 4; ++i) result.w16[i] = alu_operand[1].w16[i] << alu_operand[0].w16[i];
        EW8:  for (int i = 0; i < 8; ++i) result.w8[i] = alu_operand[1].w8[i] << alu_operand[0].w8[i];
      endcase
      VSRL:
      unique case (vew_i)
        EW64: for (int i = 0; i < 1; ++i) result.w64[i] = alu_operand[1].w64[i] >> alu_operand[0].w64[i];
        EW32: for (int i = 0; i < 2; ++i) result.w32[i] = alu_operand[1].w32[i] >> alu_operand[0].w32[i];
        EW16: for (int i = 0; i < 4; ++i) result.w16[i] = alu_operand[1].w16[i] >> alu_operand[0].w16[i];
        EW8:  for (int i = 0; i < 8; ++i) result.w8[i] = alu_operand[1].w8[i] >> alu_operand[0].w8[i];
      endcase
      VSRA:
      unique case (vew_i)
        EW64: for (int i = 0; i < 1; ++i) result.w64[i] = $signed(alu_operand[1].w64[i]) >>> alu_operand[0].w64[i];
        EW32: for (int i = 0; i < 2; ++i) result.w32[i] = $signed(alu_operand[1].w32[i]) >>> alu_operand[0].w32[i];
        EW16: for (int i = 0; i < 4; ++i) result.w16[i] = $signed(alu_operand[1].w16[i]) >>> alu_operand[0].w16[i];
        EW8:  for (int i = 0; i < 8; ++i) result.w8[i] = $signed(alu_operand[1].w8[i]) >>> alu_operand[0].w8[i];
      endcase
      // TODO: support masked VMERGE
      VMERGE: result.w64[0] = alu_operand[0];
      default: result = 'b0;
    endcase
  end

endmodule : valu
