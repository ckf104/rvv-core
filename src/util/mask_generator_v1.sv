`include "core_pkg.svh"

module mask_generator_v1
  import core_pkg::*;
#(

) (
  input  logic      first_req_i,
  input  logic      last_req_i,
  input  ele_cnt_t  skip_first_i,
  input  ele_cnt_t  skip_last_i,
  output vrf_strb_t mask_o
);
  vrf_strb_t vstart_mask, vl_mask;

  // It's possible that both `first_req_i` and `last_req_i` are asserted.
  always_comb begin : mask_comb
    if (last_req_i) vl_mask = {$bits(vrf_strb_t) {1'b1}} >> skip_last_i;
    else vl_mask = {VRFStrbWidth{1'b1}};

    if (first_req_i) vstart_mask = ~((1 << skip_first_i) - 1);
    else vstart_mask = {VRFStrbWidth{1'b1}};

    mask_o = vstart_mask & vl_mask;
  end

endmodule : mask_generator_v1
