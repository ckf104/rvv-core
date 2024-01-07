`ifndef _CORE_PKG_SVH
`define _CORE_PKG_SVH

`include "rvv_pkg.svh"
`include "riscv_pkg.svh"

package core_pkg;

  localparam int unsigned ELEN = 64;
  localparam int unsigned ELENB = ELEN / 8;

`ifdef VLEN
  localparam int unsigned VLEN = `VLEN;
`else
  localparam int unsigned VLEN = 1024;
`endif

`ifdef NrLane
  localparam int unsigned NrLane = `NrLane;
`else
  localparam int unsigned NrLane = 1;
`endif
  // TODO: assert NrLane and NrBank are power of 2
  localparam int unsigned LogNrLane = $clog2(NrLane);

  localparam int unsigned VLENB = VLEN / 8;
  localparam int unsigned MAXVL = VLEN;
  localparam int unsigned VLWidth = $clog2(MAXVL + 1);
  localparam int unsigned LaneVLWidth = VLWidth - LogNrLane;

  // Bank number of vector register file slice in
  // each lane. Assume it should be power of 2 currently.
  localparam int unsigned NrBank = 8;
  localparam int unsigned VRFWordWidth = 64;
  localparam int unsigned VRFWordWidthB = VRFWordWidth / 8;
  localparam int unsigned VRFStrbWidth = VRFWordWidthB;
  localparam int unsigned VRFSize = VLEN * rvv_pkg::NrVReg;
  localparam int unsigned RegSliceNumWords = VLEN / NrLane / VRFWordWidth;
  localparam int unsigned VRFSliceNumWords = RegSliceNumWords * rvv_pkg::NrVReg;
  localparam int unsigned VRFSlicePerBankNumWords = VRFSliceNumWords / NrBank;

  localparam int unsigned InsnIDWidth = 3;
  localparam int unsigned InsnIDNum = 1 << InsnIDWidth;

  typedef logic [InsnIDWidth-1:0] insn_id_t;
  typedef logic [$clog2(VRFSliceNumWords)-1:0] vrf_addr_t;
  typedef logic [$clog2(VRFSlicePerBankNumWords)-1:0] bank_addr_t;
  typedef logic [$clog2(NrBank)-1:0] bank_id_t;
  typedef logic [VRFWordWidth-1:0] vrf_data_t;
  typedef logic [VRFStrbWidth-1:0] vrf_strb_t;
  typedef logic [VLWidth-1:0] vlen_t;
  typedef logic [LaneVLWidth-1:0] lane_vlen_t;
  typedef logic [4:0] vreg_t;

  // Element width for vrf storage
  typedef enum logic [2:0] {
    VRFEW8  = 3'b000,
    VRFEW16 = 3'b001,
    VRFEW32 = 3'b010,
    VRFEW64 = 3'b011,
    VRFEW1  = 3'b111
  } vrfew_e;

  // Currently supported instructions
  typedef enum logic [4:0] {
    VADD,
    VSUB,
    VSLL,
    VSRL,
    VSRA,
    VMERGE,
    VSE
  } vop_e;

  typedef enum logic {
    Masked,
    UnMasked
  } vmask_e;

  localparam int unsigned NrOpQueue = 3;
  // verilog_format: off
  typedef enum logic [$clog2(NrOpQueue)-1:0] {
    ALUA,
    ALUB,
    StoreOp
  } op_queue_e;
  // verilog_format: on

  localparam int unsigned NrVFU = 2;
  localparam int unsigned NrLaneVFU = 1;
  typedef enum logic {
    VALU,
    VLSU
  } vfu_e;

  typedef struct packed {
    vlen_t           vle;
    vlen_t           vstart;
    rvv_pkg::vtype_t vtype;
  } vec_context_t;

  typedef struct packed {
    vreg_t         vs1;
    vreg_t         vs2;
    vreg_t         vd;
    vop_e          vop;
    vlen_t         vlB;
    rvv_pkg::vew_e vew;
    logic [1:0]    use_vs;
    vrf_data_t     scalar_op;
    insn_id_t      insn_id;
    // indicate a new req;
    logic          flip_bit;
  } issue_req_t;

  typedef struct packed {
    vreg_t                vs1;
    vreg_t                vs2;
    logic [NrOpQueue-1:0] queue_req;
    //rvv_pkg::vew_e vew_vs1;
    //rvv_pkg::vew_e vew_vs2;
    vlen_t                vlB;
  } op_req_t;

  typedef struct packed {
    vop_e          vop;
    rvv_pkg::vew_e vew;
    vlen_t         vlB;
    logic [1:0]    use_vs;
    vrf_addr_t     waddr;
    vrf_data_t     scalar_op;
    insn_id_t      insn_id;
  } vfu_req_t;

  // It may be not necessary for only memory
  // instruction can raise an exception in rvv.
  // We assume it's responsibility of scalar core
  // to check whether instruction is invalid.
  typedef struct packed {
    logic                 valid;
    riscv_pkg::exp_type_t cause;
    riscv_pkg::xlen_t     tval;
  } exception_t;

  // TODO: add vstart, vew arguments
  function automatic vrf_addr_t GetVRFAddr(vreg_t vreg);
    return {vreg, {$clog2(RegSliceNumWords) {1'b0}}};
  endfunction : GetVRFAddr

  function automatic vfu_e GetVFUByVOp(vop_e vop);
    unique case (vop)
      VADD, VSUB, VSLL, VSRL, VSRA, VMERGE: return VALU;
      VSE: return VLSU;
      //default: return VALU;
    endcase
  endfunction
  function automatic logic [NrOpQueue-1:0] GetOpQueue(vop_e vop, logic [1:0] use_vs);
    unique case (vop)
      VADD, VSUB, VSLL, VSRL, VSRA, VMERGE: return {{NrOpQueue - 2{1'b0}}, 2'b11 & use_vs};
      VSE: return {{NrOpQueue - 1{1'b0}}, 1'b1} << 2;
    endcase
  endfunction

  function automatic integer unsigned GetWidth(integer unsigned num_idx);
    return (num_idx > 32'd1) ? unsigned'($clog2(num_idx)) : 32'd1;
  endfunction

endpackage : core_pkg

`endif  // _CORE_PKG_SVH
