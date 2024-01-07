`include "core_pkg.svh"

module vrf
  import core_pkg::*;
#(

) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  // interface with `vrf_accesser`
  input  logic      [NrBank-1:0] req_i,
  input  bank_addr_t [NrBank-1:0] addr_i,
  // TODO: change bank to OpQueue
  input  logic      [NrBank-1:0] wen_i,
  input  vrf_data_t [NrBank-1:0] wdata_i,
  input  vrf_strb_t [NrBank-1:0] wstrb_i,
  // interface
  output vrf_data_t [NrBank-1:0] rdata_o
);
  // assume one cycle latency of reading operation
  for (genvar bank = 0; bank < NrBank; bank++) begin : gen_banks
    // TODO: gating clk
    tc_sram #(
      .NumWords (VRFSlicePerBankNumWords),
      .DataWidth(VRFWordWidth),
      .NumPorts (1)
    ) vrf_sram (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .req_i  (req_i[bank]),
      .we_i   (wen_i[bank]),
      .rdata_o(rdata_o[bank]),
      .wdata_i(wdata_i[bank]),
      .be_i   (wstrb_i[bank]),
      .addr_i (addr_i[bank])
    );
  end : gen_banks

endmodule : vrf
