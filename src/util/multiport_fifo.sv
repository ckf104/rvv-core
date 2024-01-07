`include "core_pkg.svh"

// This fifo has one write port and multiple read ports. Each read port has
// a corresponding read pointer, element counter, `empty` signal to indicate
// if output data is valid. But there is only one `full` signal, one element
// isn't deemed as popped until all read ports have popped it.
// For our use case, we assume that:
// read_pointer[0] >= read_pointer[1] >= ... >= read_pointer[NrReadPort-1]
// So we pop one element when `pop_i[NrReadPort-1] == 1'b1`
// TODO: Add assertion and remove reset of `mem_q`
module multiport_fifo #(
  parameter int unsigned NrReadPort = 2,
  parameter int unsigned DataWidth = 32,  // default data width if the fifo is of type logic
  parameter int unsigned Depth = 8,  // depth can be arbitrary from 0 to 2**32
  parameter type dtype = logic [DataWidth-1:0],
  // DO NOT OVERWRITE THIS PARAMETER
  parameter int unsigned AddrDepth = core_pkg::GetWidth(Depth)  // address width
) (
  input  logic                  clk_i,    // Clock
  input  logic                  rst_ni,   // Asynchronous reset active low
  input  logic                  flush_i,  // flush the queue
  // status flags
  output logic                  full_o,   // queue is full
  output logic [NrReadPort-1:0] empty_o,  // queue is empty
  // as long as the queue is not full we can push new data
  input  dtype                  data_i,   // data to push into the queue
  input  logic                  push_i,   // data is valid and can be pushed to the queue
  // as long as the queue is not empty we can pop new elements
  output dtype [NrReadPort-1:0] data_o,   // output data
  input  logic [NrReadPort-1:0] pop_i     // forward the read pointer
);
  typedef logic [AddrDepth-1:0] addr_t;
  typedef logic [AddrDepth:0] cnt_t;

  // clock gating control
  logic gate_clock;
  // pointer to the read and write section of the queue
  addr_t [NrReadPort-1:0] read_pointer_n, read_pointer_q;
  addr_t write_pointer_n, write_pointer_q;
  // keep a counter to keep track of the current queue status
  // this integer will be truncated by the synthesis tool
  cnt_t [NrReadPort-1:0] status_cnt_n, status_cnt_q;
  // actual memory
  dtype [Depth - 1:0] mem_n, mem_q;


  assign full_o = (status_cnt_q[NrReadPort-1] == Depth[AddrDepth:0]);
  for (genvar i = 0; i < NrReadPort; ++i) begin : gen_output_signal
    assign empty_o[i] = (status_cnt_q[i] == 0);
    assign data_o[i]  = mem_q[read_pointer_q[i]];
  end
  // status flags

  // read and write queue logic
  always_comb begin : read_write_comb
    // default assignment
    read_pointer_n  = read_pointer_q;
    write_pointer_n = write_pointer_q;
    status_cnt_n    = status_cnt_q;
    mem_n           = mem_q;
    gate_clock      = 1'b1;

    // push a new element to the queue
    if (push_i && ~full_o) begin
      // push the data onto the queue
      mem_n[write_pointer_q] = data_i;
      // un-gate the clock, we want to write something
      gate_clock             = 1'b0;
      // increment the write counter
      // this is dead code when Depth is a power of two
      if (write_pointer_q == Depth[AddrDepth-1:0] - 1) write_pointer_n = '0;
      else write_pointer_n = write_pointer_q + 1;
      // increment the overall counter
      for (int i = 0; i < NrReadPort; ++i) begin
        status_cnt_n[i] = status_cnt_n[i] + 1;
      end
    end
    for (int i = 0; i < NrReadPort; ++i) begin
      if (pop_i[i] && ~empty_o[i]) begin
        // read from the queue is a default assignment
        // but increment the read pointer...
        // this is dead code when Depth is a power of two
        if (read_pointer_n[i] == Depth[AddrDepth-1:0] - 1) read_pointer_n[i] = '0;
        else read_pointer_n[i] = read_pointer_q[i] + 1;
        // ... and decrement the overall count
        status_cnt_n[i] = status_cnt_n[i] - 1;
      end
    end

  end

  // sequential process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      read_pointer_q  <= '0;
      write_pointer_q <= '0;
      status_cnt_q    <= '0;
    end else begin
      if (flush_i) begin
        read_pointer_q  <= '0;
        write_pointer_q <= '0;
        status_cnt_q    <= '0;
      end else begin
        read_pointer_q  <= read_pointer_n;
        write_pointer_q <= write_pointer_n;
        status_cnt_q    <= status_cnt_n;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      mem_q <= '0;
    end else if (!gate_clock) begin
      mem_q <= mem_n;
    end
  end

endmodule : multiport_fifo
