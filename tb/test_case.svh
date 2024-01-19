`ifndef _TEST_CASE_SVH
`define _TEST_CASE_SVH

`ifdef GENERATE_CASE1

localparam int unsigned NumStimulus = 2;

// vmv.v.i v2, 1  (vl = 18, vstart = 1)
// vse32.v v2,(ra)
`define TEST_CASE \
    vl   = 'd8; \
    vtype = vtype_t'{vsew   : EW32, \
    vlmul  : LMUL_1, default: 'b0}; \
    stim_array[0] = stimulus'{                                             \
      insn       : 32'h5e00b157,                                           \
      insn_id    : 'd0,                                                    \
      vec_context: vec_context_t'{vl   : 18, vtype : vtype, vstart: 'b1} \
    };                                                                     \
    stim_array[1] = stimulus'{                                             \
      insn: 32'h0200e127,                                                  \
      insn_id: 'd1,                                                        \
      vec_context: vec_context_t'{vl   : 20, vtype : vtype, vstart: 'b0} \
    };

`elsif GENERATE_CASE2

localparam int unsigned NumStimulus = 4;

// vmv.v.i v2, 1
// vmv.v.i v3, 2
// vadd.vv v1, v2, v3
// vse64.v v1,(ra)
`define TEST_CASE \
    vl   = 'd8; \
    vtype = vtype_t'{vsew   : EW64, \
    vlmul  : LMUL_1, default: 'b0}; \
    stim_array[0] = stimulus'{                                             \
      insn       : 32'h5e00b157,                                           \
      insn_id    : 'd0,                                                    \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[1] = stimulus'{                                             \
      insn: 32'h5e0131d7,                                                  \
      insn_id: 'd1,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[2] = stimulus'{                                             \
      insn: 32'h022180d7,                                                  \
      insn_id: 'd2,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[3] = stimulus'{                                             \
      insn: 32'h0200f0a7,                                                  \
      insn_id: 'd3,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };

`elsif GENERATE_CASE3

localparam int unsigned NumStimulus = 4;

// vle64.v v2, (x1)
// vle64.v v3, (x2)
// vadd.vv v1, v2, v3
// vse64.v v1,(ra)
`define TEST_CASE \
    vl   = 'd8; \
    vtype = vtype_t'{vsew   : EW64, \
    vlmul  : LMUL_1, default: 'b0}; \
    stim_array[0] = stimulus'{                                             \
      insn       : 32'h0200f107,                                           \
      insn_id    : 'd0,                                                    \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[1] = stimulus'{                                             \
      insn: 32'h02017187,                                                  \
      insn_id: 'd1,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[2] = stimulus'{                                             \
      insn: 32'h022180d7,                                                  \
      insn_id: 'd2,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[3] = stimulus'{                                             \
      insn: 32'h0200f0a7,                                                  \
      insn_id: 'd3,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };

`elsif GENERATE_CASE4

localparam int unsigned NumStimulus = 4;

// vle32.v v2, (x1)
// vmv.v.i v3, 1
// vadd.vv v1, v2, v3
// vse32.v v1,(ra)
`define TEST_CASE \
    vl   = 'd16; \
    vtype = vtype_t'{vsew   : EW32, \
    vlmul  : LMUL_1, default: 'b0}; \
    stim_array[0] = stimulus'{                                             \
      insn       : 32'h0200e107,                                           \
      insn_id    : 'd0,                                                    \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[1] = stimulus'{                                             \
      insn: 32'h5e00b1d7,                                                  \
      insn_id: 'd1,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[2] = stimulus'{                                             \
      insn: 32'h022180d7,                                                  \
      insn_id: 'd2,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };                                                                     \
    stim_array[3] = stimulus'{                                             \
      insn: 32'h0200e0a7,                                                  \
      insn_id: 'd3,                                                        \
      vec_context: vec_context_t'{vl   : vl, vtype : vtype, vstart: 'b0} \
    };

`elsif GENERATE_CASE5

localparam int unsigned NumStimulus = 4;

// vmv.v.i v2, 1  (vl = 17, vstart = 1)
// vmv.v.i v3, 2  (vl = 18, vstart = 2)
// vadd.vv v1, v2, v3 (vl = 19, vstart = 3)
// vse32.v v1,(ra) (vl = 20, vstart = 0)
// result: 0, 0, 0, 3(reapting 14 times), 2, 0, 0
`define TEST_CASE \
    vl   = 'd16; \
    vtype = vtype_t'{vsew   : EW32, \
    vlmul  : LMUL_1, default: 'b0}; \
    stim_array[0] = stimulus'{                                             \
      insn       : 32'h5e00b157,                                           \
      insn_id    : 'd0,                                                    \
      vec_context: vec_context_t'{vl   : 17, vtype : vtype, vstart: 'd1} \
    };                                                                     \
    stim_array[1] = stimulus'{                                             \
      insn: 32'h5e0131d7,                                                  \
      insn_id: 'd1,                                                        \
      vec_context: vec_context_t'{vl   : 18, vtype : vtype, vstart: 'd2} \
    };                                                                     \
    stim_array[2] = stimulus'{                                             \
      insn: 32'h022180d7,                                                  \
      insn_id: 'd2,                                                        \
      vec_context: vec_context_t'{vl   : 19, vtype : vtype, vstart: 'd3} \
    };                                                                     \
    stim_array[3] = stimulus'{                                             \
      insn: 32'h0200e0a7,                                                  \
      insn_id: 'd3,                                                        \
      vec_context: vec_context_t'{vl   : 20, vtype : vtype, vstart: 'd0} \
    };

`endif

`endif  // _TEST_CASE_SVH
