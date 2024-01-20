`include "core_pkg.svh"
`include "rvv_pkg.svh"

module mem_shuffler_v0
  import core_pkg::*;
  import rvv_pkg::*;
#(
) (
  // Input data
  input  vrf_data_t                  data_i,
  input  logic       [LogNrLane-1:0] sel,
  input  logic                       is_first,
  input  bytes_cnt_t                 skip_first,
  input  logic                       is_last,
  input  bytes_cnt_t                 skip_last,
  // Data element width
  input  vew_e                       sew,
  // Output data and mask
  output vrf_data_t  [   NrLane-1:0] data_o,
  output vrf_strb_t  [   NrLane-1:0] mask_o
);
  // Here we assumed that vrf width is 64 bits
  `include "shuffle_table_vrf64_lane2_sew8.svh"
  `include "shuffle_table_vrf64_lane2_sew16.svh"
  `include "shuffle_table_vrf64_lane2_sew32.svh"
  `include "shuffle_table_vrf64_lane2_sew64.svh"
  `include "shuffle_table_vrf64_lane4_sew8.svh"
  `include "shuffle_table_vrf64_lane4_sew16.svh"
  `include "shuffle_table_vrf64_lane4_sew32.svh"
  `include "shuffle_table_vrf64_lane4_sew64.svh"
  `include "shuffle_table_vrf64_lane8_sew8.svh"
  `include "shuffle_table_vrf64_lane8_sew16.svh"
  `include "shuffle_table_vrf64_lane8_sew32.svh"
  `include "shuffle_table_vrf64_lane8_sew64.svh"
  `include "shuffle_table_vrf64_lane16_sew8.svh"
  `include "shuffle_table_vrf64_lane16_sew16.svh"
  `include "shuffle_table_vrf64_lane16_sew32.svh"
  `include "shuffle_table_vrf64_lane16_sew64.svh"

vrf_strb_t init_mask;
  logic [ByteBlock-1:0] inmask, outmask;

  mask_generator_v1 #(
    .MaskWidth(VRFWordWidthB)
  ) mask_generator (
    .first_req_i (is_first),
    .last_req_i  (is_last),
    .skip_first_i({1'b0, skip_first}),
    .skip_last_i ({1'b0, skip_last}),
    .mask_o      (init_mask)
  );

  assign mask_o = outmask;

  typedef logic [7:0] data8_t;
  data8_t [VRFWordWidthB-1:0] init_data;
  data8_t [ByteBlock-1:0] indata, outdata;

  assign init_data = data_i;
  assign data_o    = outdata;

  always_comb begin : indata_inmask_logic
    indata = 'b0;
    inmask = 'b0;
    for (int unsigned i = 0; i < VRFWordWidthB; ++i) begin
      indata[sel*VRFWordWidthB+i] = init_data[i];
      inmask[sel*VRFWordWidthB+i] = init_mask[i];
    end
  end

  generate
    if (NrLane == 1) begin : case_lane_1
      always_comb begin
        outdata = indata;
        outmask = inmask;
      end
    end : case_lane_1
    else if (NrLane == 2) begin : case_lane_2
      always_comb begin
        unique case (sew)
          EW8: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane2_sew8[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane2_sew8[i]];
            end
          end
          EW16: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane2_sew16[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane2_sew16[i]];
            end
          end
          EW32: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane2_sew32[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane2_sew32[i]];
            end
          end
          EW64: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane2_sew64[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane2_sew64[i]];
            end
          end
        endcase
      end
    end else if (NrLane == 4) begin : case_lane_4
      always_comb begin
        unique case (sew)
          EW8: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane4_sew8[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane4_sew8[i]];
            end
          end
          EW16: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane4_sew16[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane4_sew16[i]];
            end
          end
          EW32: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane4_sew32[i]];
              outmask[i] = indata[shuffle_table_vrf64_lane4_sew32[i]];
            end
          end
          EW64: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane4_sew64[i]];
              outmask[i] = indata[shuffle_table_vrf64_lane4_sew64[i]];
            end
          end
        endcase
      end
    end else if (NrLane == 8) begin : case_lane_8
      always_comb begin
        unique case (sew)
          EW8: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane8_sew8[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane8_sew8[i]];
            end
          end
          EW16: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane8_sew16[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane8_sew16[i]];
            end
          end
          EW32: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane8_sew32[i]];
              outmask[i] = indata[shuffle_table_vrf64_lane8_sew32[i]];
            end
          end
          EW64: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane8_sew64[i]];
              outmask[i] = indata[shuffle_table_vrf64_lane8_sew64[i]];
            end
          end
        endcase
      end
    end else if (NrLane == 16) begin : case_lane_16
      always_comb begin
        unique case (sew)
          EW8: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane16_sew8[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane16_sew8[i]];
            end
          end
          EW16: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane16_sew16[i]];
              outmask[i] = inmask[shuffle_table_vrf64_lane16_sew16[i]];
            end
          end
          EW32: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane16_sew32[i]];
              outmask[i] = indata[shuffle_table_vrf64_lane16_sew32[i]];
            end
          end
          EW64: begin
            for (int unsigned i = 0; i < ByteBlock; ++i) begin
              outdata[i] = indata[shuffle_table_vrf64_lane16_sew64[i]];
              outmask[i] = indata[shuffle_table_vrf64_lane16_sew64[i]];
            end
          end
        endcase
      end
    end
  endgenerate

endmodule : mem_shuffler_v0
