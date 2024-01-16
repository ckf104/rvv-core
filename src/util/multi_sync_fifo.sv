
// `multi_sync_fifo` will create multiple FIFOs, which push and pop data synchronously.
// TODO: Add assertion and remove reset of `mem_q`
module multi_sync_fifo #(
  parameter int unsigned NumFifo = 2,
  parameter bit FALL_THROUGH = 1'b0,  // fifo is in fall-through mode
  parameter int unsigned DataWidth = 32,  // default data width if the fifo is of type logic
  parameter int unsigned Depth = 8,  // depth can be arbitrary from 0 to 2**32
  parameter type dtype = logic [DataWidth-1:0],
  // DO NOT OVERWRITE THIS PARAMETER
  parameter int unsigned AddrDepth = (Depth > 1) ? $clog2(Depth) : 1
) (
  input  logic                 clk_i,         // Clock
  input  logic                 rst_ni,        // Asynchronous reset active low
  input  logic                 flush_i,       // flush the queue
  // status flags
  output logic                 full_o,        // queue is full
  output logic                 empty_o,       // queue is empty
  output logic [AddrDepth-1:0] usage_o,       // fill pointer
  // as long as the queue is not full we can push new data
  input  dtype [  NumFifo-1:0] data_i,        // data to push into the queue
  input  logic                 push_i,        // data is valid and can be pushed to the queue
  // as long as the queue is not empty we can pop new elements
  output dtype [  NumFifo-1:0] data_o,        // output data
  output logic [  NumFifo-1:0] data_valid_o,
  // We assume that gnt will be asserted iff data is valid
  input  logic [  NumFifo-1:0] gnt_i,         // pop head from queue
  output logic                 pop_o
);
  logic [NumFifo-1:0] mask_n, mask_q;
  // pointer to the read and write section of the queue
  logic [AddrDepth - 1:0] read_pointer_n, read_pointer_q, write_pointer_n, write_pointer_q;
  // keep a counter to keep track of the current queue status
  // this integer will be truncated by the synthesis tool
  logic [AddrDepth:0] status_cnt_n, status_cnt_q;
  // actual memory
  dtype [Depth - 1:0][NumFifo-1:0] mem_n, mem_q;

  assign usage_o = status_cnt_q[AddrDepth-1:0];
  assign full_o  = (status_cnt_q == Depth[AddrDepth:0]);
  assign empty_o = (status_cnt_q == 0) & ~(FALL_THROUGH & push_i);
  assign mask_n  = mask_q & ~gnt_i;
  // status flags

  // read and write queue logic
  always_comb begin : read_write_comb
    // default assignment
    read_pointer_n  = read_pointer_q;
    write_pointer_n = write_pointer_q;
    status_cnt_n    = status_cnt_q;
    data_o          = mem_q[read_pointer_q];
    data_valid_o    = mask_q & {NumFifo{~empty_o}};
    pop_o           = mask_n == 'b0;
    mem_n           = mem_q;

    // push a new element to the queue
    if (push_i && ~full_o) begin
      // push the data onto the queue
      mem_n[write_pointer_q] = data_i;
      // increment the write counter
      // this is dead code when DEPTH is a power of two
      if (write_pointer_q == Depth[AddrDepth-1:0] - 1) write_pointer_n = '0;
      else write_pointer_n = write_pointer_q + 1;
      // increment the overall counter
      status_cnt_n = status_cnt_q + 1;
    end

    if (pop_o) begin
      // read from the queue is a default assignment
      // but increment the read pointer...
      // this is dead code when DEPTH is a power of two
      if (read_pointer_n == Depth[AddrDepth-1:0] - 1) read_pointer_n = '0;
      else read_pointer_n = read_pointer_q + 1;
      // ... and decrement the overall count
      status_cnt_n = status_cnt_q - 1;
    end

    // keep the count pointer stable if we push and pop at the same time
    if (push_i && pop_o && ~full_o && ~empty_o) status_cnt_n = status_cnt_q;

    // FIFO is in pass through mode -> do not change the pointers
    if (FALL_THROUGH && (status_cnt_q == 'b0) && push_i) begin
      data_o = data_i;
      if (pop_o) begin
        status_cnt_n    = status_cnt_q;
        read_pointer_n  = read_pointer_q;
        write_pointer_n = write_pointer_q;
      end
    end
  end

  // sequential process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      read_pointer_q  <= 'b0;
      write_pointer_q <= 'b0;
      status_cnt_q    <= 'b0;
      mask_q          <= {NumFifo{1'b1}};
    end else begin
      if (flush_i) begin
        read_pointer_q  <= 'b0;
        write_pointer_q <= 'b0;
        status_cnt_q    <= 'b0;
        mask_q          <= {NumFifo{1'b1}};
      end else begin
        read_pointer_q  <= read_pointer_n;
        write_pointer_q <= write_pointer_n;
        status_cnt_q    <= status_cnt_n;
        mask_q          <= mask_n == 'b0 ? ~mask_n : mask_n;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      mem_q <= '0;
    end else begin
      mem_q <= mem_n;
    end
  end

endmodule  // multi_sync_fifo
