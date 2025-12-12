//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Output FIFO Component With AXI-Stream Interface
	
module fifo_out #(
		parameter OUTW = 12,	//Size of data
		parameter DEPTH = 19,	//Maximum capacity of the FIFO
		localparam LOGDEPTH = $clog2(DEPTH)	//log-base 2 (rounded up to the nearest integer) of DEPTH
	)(
		input clk,	//System clock
		input reset,	//Synchronous reset
		
		//AXIS input interface
		input [OUTW-1:0] IN_AXIS_TDATA,
		input IN_AXIS_TVALID,
		output logic IN_AXIS_TREADY, 
		
		//AXIS output interface
		output logic [OUTW-1:0] OUT_AXIS_TDATA,
		output logic OUT_AXIS_TVALID,
		input OUT_AXIS_TREADY
	);
	
	// Internal signals
	logic [DEPTH:0] capacity;	//for keeping track of the number of entries in the FIFO
	logic [LOGDEPTH-1:0] write_address, read_address;	//read & write addresses to be sent to the memory
	logic [LOGDEPTH-1:0] tail_next;
	logic write_enable, read_enable;
	logic empty, full;

	assign write_enable = IN_AXIS_TVALID && IN_AXIS_TREADY;	//write enable signal for the memory, head logic, and capacity logic
	assign read_enable = OUT_AXIS_TVALID && OUT_AXIS_TREADY;	//read enable signal tail logic and capacity logic

	assign empty = (capacity == DEPTH);
	assign full = (capacity == 0);

	assign OUT_AXIS_TVALID = !empty; // If FIFO is not empty, then OUT_AXIS_TVALID = 1
	assign IN_AXIS_TREADY = (capacity > 0) || ((capacity == 0) && read_enable);
	//assign IN_AXIS_TREADY = !full || (full && read_enable); // If FIFO is not full, then IN_AXIS_TREADY = 1

	//Instantiation of the FIFO's dual-port memory
	memory_dual_port #(OUTW, DEPTH) mem_inst(
		.clk(clk), .data_in(IN_AXIS_TDATA), .wr_en(write_enable), 
		.write_addr(write_address), .read_addr(tail_next), .data_out(OUT_AXIS_TDATA));	

	// --------------------------------------------
	// Head logic for FIFO
	// --------------------------------------------

	//Head (Write Address) Logic (occurs on every clock edge)
	always_ff @(posedge clk) begin
		if (reset) 
			//initialize write address to 0
			write_address <= 0;
		else if (write_enable) 
			//increment write address
			if (write_address == DEPTH - 1)
				write_address <= 0;
			else
				write_address <= write_address + 1; 
	end		 
	
	// --------------------------------------------
	// Tail logic for FIFO
	// --------------------------------------------

	//Tail (Read Address) Logic (occurs on every clock edge)
	always_ff @(posedge clk) begin
		if (reset) 
			read_address <= 0;

		else if (read_enable) 	// reset == 0 && read_enable == 1
			if (read_address == DEPTH-1)
				read_address <= 0;
			else
				read_address <= read_address + 1;
	end	
	
	// For tail logic
	always_comb begin
		if (read_enable)
			if (read_address == DEPTH-1)
				tail_next = 0;
			else
				tail_next = read_address + 1;
		else
			tail_next = read_address;
	end	

	// --------------------------------------------
	// Capacity Logic
	// --------------------------------------------

	always_ff @(posedge clk) begin
		if (reset) 
			//empty the FIFO
			capacity <= DEPTH;

		 else 	//unasserted reset
		 	case ({write_enable, read_enable})
				2'b00: capacity <= capacity;
				2'b01: capacity <= capacity + 1;
				2'b10: capacity <= capacity - 1;
				2'b11: capacity <= capacity;
				default: capacity <= capacity;

			endcase
	end

endmodule	