`ifndef _RISCV_PKG_SVH
`define _RISCV_PKG_SVH

package riscv_pkg;
// verilator lint_off UNUSEDPARAM

  localparam XLEN = 64;
  typedef logic [XLEN-1:0] xlen_t;

  typedef logic [3:0] exp_type_t;
  localparam exp_type_t INSTR_ADDR_MISALIGNED = 0;
  localparam exp_type_t INSTR_ACCESS_FAULT = 1;  // Illegal access as governed by PMPs and PMAs
  localparam exp_type_t ILLEGAL_INSTR = 2;
  localparam exp_type_t BREAKPOINT = 3;
  localparam exp_type_t LD_ADDR_MISALIGNED = 4;
  localparam exp_type_t LD_ACCESS_FAULT = 5;  // Illegal access as governed by PMPs and PMAs
  localparam exp_type_t ST_ADDR_MISALIGNED = 6;
  localparam exp_type_t ST_ACCESS_FAULT = 7;  // Illegal access as governed by PMPs and PMAs
  localparam exp_type_t ENV_CALL_UMODE = 8;  // environment call from user mode
  localparam exp_type_t ENV_CALL_SMODE = 9;  // environment call from supervisor mode
  localparam exp_type_t ENV_CALL_MMODE = 11;  // environment call from machine mode
  localparam exp_type_t INSTR_PAGE_FAULT = 12;  // Instruction page fault
  localparam exp_type_t LOAD_PAGE_FAULT = 13;  // Load page fault
  localparam exp_type_t STORE_PAGE_FAULT = 15;  // Store page fault

// verilator lint_on UNUSEDPARAM
endpackage : riscv_pkg

`endif  // _RISCV_PKG_SVH
