//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Output FIFO Component With AXI-Stream Interface
	
module fifo_out #(
		parameter OUTW = 24,	//Size of data
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
	
	// Internal registers
	logic [$clog2(DEPTH+1)-1:0] capacity;	//for keeping track of the number of entries in the FIFO
	logic [LOGDEPTH-1:0] write_address, read_address;	//read & write addresses to be sent to the memory
	logic [LOGDEPTH-1:0] tail_next;
	logic write_enable = IN_AXIS_TVALID && IN_AXIS_TREADY;	//write enable signal for the memory, head logic, and capacity logic
	logic read_enable = OUT_AXIS_TVALID && OUT_AXIS_TREADY;	//read enable signal tail logic and capacity logic

	//Instantiation of the FIFO's dual-port memory
	memory_dual_port #(OUTW, DEPTH) mem_inst(.clk(clk), .data_in(IN_AXIS_TDATA), .wr_en(write_enable), .write_addr(write_address), .read_addr(tail_next), .data_out(OUT_AXIS_TDATA));	
	
	// --------------------------------------------
	// Head logic for FIFO
	// --------------------------------------------

	//Head (Write Address) Logic (occurs on every clock edge)
	always_ff @(posedge clk) begin
		if (reset == 1) begin
			//initialize write address to 0
			write_address <= 0;
		end else if (write_enable == 1) begin
			//increment write address
			write_address <= write_address + 1; 
		end
	end

	// TREADY signal combinational logic for head logic
	always_comb begin
		if (capacity == 0)	//FIFO is full; no space for new data
			IN_AXIS_TREADY = 0;
		else	//FIFO has space for new data to be written
			IN_AXIS_TREADY = 1;
	end			 
	
	// --------------------------------------------
	// Tail logic for FIFO
	// --------------------------------------------
	
	//Tail (Read Address) Logic (occurs on every clock edge)
	always_ff @(posedge clk) begin
		if (reset == 1) begin
			read_address <= 0;

		end else if (read_enable) begin	// reset == 0 && read_enable == 1
			if (read_address == DEPTH-1)
				read_address <= 0;
			else
				read_address <= read_address + 1;
			
		end	
		
	end	
	
	// For tail logic
	always_comb begin
		if (!read_enable)
			tail_next = read_address;

		else if (read_address == DEPTH-1)
			tail_next = 0;

		else
			tail_next = read_address + 1;
			
		/*
		if (capacity == DEPTH)	//FIFO is empty and has no data to be read
			OUT_AXIS_TVALID = 0;

		end else begin	// FIFO is not full; assert OUT_AXIS_TVALID; FIFO has data to be read
			OUT_AXIS_TVALID = 1;

		end
		*/
	end	

	//Capacity Logic
	always_ff @(posedge clk) begin
		if (reset == 1) begin
			//empty the FIFO
			capacity <= DEPTH;
		end else begin	//unasserted reset
			if (write_enable == 1)
				//write is enabled; decrement capacity
				capacity = capacity - 1;
			else if (read_enable == 1)
				//read is enabled; increment capacity
				capacity = capacity + 1;
			end	
	end
endmodule	
