`ifndef _CORE_PKG_SVH
`define _CORE_PKG_SVH

`include "rvv_pkg.svh"
`include "riscv_pkg.svh"

package core_pkg;
  // verilator lint_off UNUSEDPARAM

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
  localparam int unsigned NrLane = 2;
`endif
  localparam int unsigned NrLaneMinusOne = NrLane - 1;
  // TODO: assert NrLane and NrBank are power of 2
  localparam int unsigned LogNrLane = $clog2(NrLane);

  localparam int unsigned VLENB = VLEN / 8;
  localparam int unsigned MAXVL = VLEN;
  localparam int unsigned VLWidth  /*verilator public*/ = $clog2(MAXVL + 1);
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

  // The total bytes of each lane accessing vrf once are `ByteBlock`
  localparam int unsigned ByteBlock = VRFWordWidthB * NrLane;
  localparam int unsigned ByteBlockWidth = $clog2(ByteBlock);
  localparam int unsigned AccessCntWidth = VLWidth - ByteBlockWidth;
  localparam int unsigned WordAccCntWidth = VLWidth - $clog2(VRFWordWidthB);

  localparam int unsigned InsnIDWidth  /*verilator public*/ = 3;
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
  // The main purpose of introducing `ele_cnt_t` is to count skipped leading bytes
  // and trailing bytes caused by non-aligned vstart or vl. It's possible the whole
  // vrf word is skipped. Therefore the width of `ele_cnt_t` is `clog2(VRFWordWidthB) + 1`.
  typedef logic [$clog2(VRFWordWidthB):0] ele_cnt_t;
  // For the same purpose as introducing `ele_cnt_t`, we typedef `bytes_cnt_t` for
  // non-aligned vstart or vl in memory instruction, except that it's impossible to skip
  // the whole vrf word. So we can save one bit.
  typedef logic [$clog2(VRFWordWidthB)-1:0] bytes_cnt_t;
  // Counter type of access into each lane
  typedef logic [AccessCntWidth-1:0] acc_cnt_t;
  // Counter type of accessing by VRFWord
  typedef logic [WordAccCntWidth-1:0] word_cnt_t;

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
    VSE,
    VLE
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

  // NrVFU indicates the number of vector functional units and
  // determines width of vfu_ready, done singals.
  localparam int unsigned NrVFU = 3;

  // NrLaneVFU indicates the number of vector functional units within
  // each lane and determines width of vfu_ready, done singals from lane.
  localparam int unsigned NrLaneVFU = 1;

  // NrWriteBackVFU indicates the number of VFU will write back result to vrf
  localparam int unsigned NrWriteBackVFU = 2;

  // Index used by NrVFU, NRLaneVFU
  typedef enum logic [1:0] {
    VALU,
    VLU,
    VSU
  } vfu_e;

  // Index used by NrWriteBackVFU
  typedef enum logic {
    WB_VALU,
    WB_VLU
  } wb_vfu_e;

  typedef struct packed {
    vlen_t           vl;
    vlen_t           vstart;
    rvv_pkg::vtype_t vtype;
  } vec_context_t  /*verilator public*/;

  localparam logic [1:0] VS1 = 2'b00;
  localparam logic [1:0] VS2 = 2'b01;
  localparam logic [1:0] VS3 = 2'b10;
  localparam logic [1:0] VD = 2'b10;

  typedef struct packed {
    vreg_t [2:0]         vs;
    logic [2:0]          use_vs;
    rvv_pkg::vew_e [2:0] vew;
    vop_e                vop;
    vlen_t               vl;
    vlen_t               vstart;
    vrf_data_t           scalar_op;
    insn_id_t            insn_id;
  } issue_req_t;

  typedef struct packed {
    vreg_t [2:0]          vs;
    rvv_pkg::vew_e [2:0]  vew;
    logic [NrOpQueue-1:0] queue_req;
    vlen_t                vl;
    vlen_t                vstart;
`ifdef DUMP_VRF_ACCESS
    insn_id_t             insn_id;
`endif
  } op_req_t;

  typedef struct packed {
    vop_e          vop;
    rvv_pkg::vew_e vew_vd;
    vlen_t         vl;
    vlen_t         vstart;
    logic [2:0]    use_vs;
    vrf_data_t     scalar_op;
    insn_id_t      insn_id;
    vreg_t         vd;
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
      VSE: return VSU;
      VLE: return VLU;
      //default: return VALU;
    endcase
  endfunction
  function automatic logic [NrOpQueue-1:0] GetOpQueue(vop_e vop, logic [2:0] use_vs);
    unique case (vop)
      VADD, VSUB, VSLL, VSRL, VSRA, VMERGE: return {{NrOpQueue - 2{1'b0}}, 2'b11 & use_vs[VS2:VS1]};
      VSE: return {{NrOpQueue - 1{1'b0}}, 1'b1} << 2;
      VLE: return {NrOpQueue{1'b0}};
    endcase
  endfunction

  function automatic integer unsigned GetWidth(integer unsigned num_idx);
    return (num_idx > 32'd1) ? unsigned'($clog2(num_idx)) : 32'd1;
  endfunction

  // verilator lint_on UNUSEDPARAM
endpackage : core_pkg

`endif  // _CORE_PKG_SVH
