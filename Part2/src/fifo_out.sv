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
	
	//Internal signals
	integer unsigned [LOGDEPTH-1:0] capacity;	//for keeping track of the number of entries in the FIFO
	logic [LOGDEPTH-1:0] write_address, read_address;	//read & write addresses to be sent to the memory  
	logic write_enable = IN_AXIS_TVALID && IN_AXIS_TREADY;	//write enable signal for the memory, head logic, and capacity logic
	logic read_enable = OUT_AXIS_TVALID && OUT_AXIS_TREADY;	//read enable signal tail logic and capacity logic
	
	//Instantiation of the FIFO's dual-port memory
	memory_dual_port #(OUTW, DEPTH) mem_inst(.clk(clk), .data_in(IN_AXIS_TDATA), .wr_en(write_enable), .write_addr(write_address), .read_addr(read_address), .data_out(OUT_AXIS_TDATA));	
	
	//Head (Write Address) Logic
	always_ff @(posedge clk) begin
		
		if (reset == 1)
			//reset write address to 0
			write_address <= 0;	
			
		else if (write_enable == 1)
			//increment write address
			write_address <= write_address + 1;  
			
		end	
		
	end
	
	//Tail (Read Address) Logic
	always_ff @(posedge clk) begin
		
		if (reset == 1) begin
			//reset output FIFO data to all 0s
			OUT_AXIS_TDATA <= {OUTW{1'b0}};	//OUTW bits wide	
			
		end else begin	//unasserted reset
			
			if (capacity == DEPTH) begin	//FIFO is empty; no data to output
				OUT_AXIS_TVALID <= 0;
			
			end else begin	//FIFO has data to be read
				OUT_AXIS_TVALID <= 1;
				
				if (OUT_AXIS_TREADY == 1) begin	 
					read_address <= ;
				end	
				
			end			 
			
		end	
		
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
		
	end
	
endmodule	
