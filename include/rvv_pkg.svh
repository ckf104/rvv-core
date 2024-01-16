`ifndef _RVV_PKG_SVH
`define _RVV_PKG_SVH

package rvv_pkg;
// verilator lint_off UNUSEDPARAM

  localparam int unsigned NrVReg = 32;
  localparam int unsigned VSEWWidth  /*verilator public*/ = 2;
  localparam int unsigned VLMULWidth  /*verilator public*/ = 3;

  // Element width for vfu operation
  typedef enum logic [VSEWWidth-1:0] {
    EW8  = 2'b00,
    EW16 = 2'b01,
    EW32 = 2'b10,
    EW64 = 2'b11
  } vew_e  /*verilator public*/;

  // Length multiplier
  typedef enum logic [VLMULWidth-1:0] {
    LMUL_1    = 3'b000,
    LMUL_2    = 3'b001,
    LMUL_4    = 3'b010,
    LMUL_8    = 3'b011,
    LMUL_RSVD = 3'b100,
    LMUL_1_8  = 3'b101,
    LMUL_1_4  = 3'b110,
    LMUL_1_2  = 3'b111
  } vlmul_e  /*verilator public*/;

  // Func3 values for vector arithmetics instructions under OpcodeV
  typedef enum logic [2:0] {
    OPIVV = 3'b000,
    OPFVV = 3'b001,
    OPMVV = 3'b010,
    OPIVI = 3'b011,
    OPIVX = 3'b100,
    OPFVF = 3'b101,
    OPMVX = 3'b110,
    OPCFG = 3'b111
  } opcodev_func3_e;

  // Func6 values for vector arithmetics instructions under OpcodeV
  typedef enum logic [5:0] {
    OPVADD   = 6'b000000,
    OPVSUB   = 6'b000010,
    OPVMERGE = 6'b010111,
    OPVSLL   = 6'b100101,
    OPVSRL   = 6'b101000,
    OPVSRA   = 6'b101001
  } opcodev_func6_e;

  // Vector type register
  typedef struct packed {
    logic   vill;
    logic   vma;
    logic   vta;
    vew_e   vsew;
    vlmul_e vlmul;
  } vtype_t;

  typedef struct packed {
    logic [31:26]   func6;
    logic           vm;
    logic [24:20]   vs2;
    logic [19:15]   vs1;
    opcodev_func3_e func3;
    logic [11:7]    vd;
    logic [6:0]     opcode;
  } varith_type_t;

  typedef struct packed {
    logic [31:29] nf;
    logic         mew;
    logic [27:26] mop;
    logic         vm;
    logic [24:20] vs2;
    logic [19:15] vs1;
    logic [14:12] width;
    logic [11:7]  vs3;
    logic [6:0]   opcode;
  } vmem_type_t;

  localparam OpcodeVec = 7'b10_101_11;
  localparam OpcodeStoreFP = 7'b01_001_11;  // opecode of vector store is the same as float store

// verilator lint_off UNUSEDPARAM
endpackage : rvv_pkg

`endif  // _RVV_PKG_SVH
