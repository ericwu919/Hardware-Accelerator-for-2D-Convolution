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
	
	integer unsigned [LOGDEPTH-1:0] count;	//for keeping count of the number of entries in the FIFO
	
	//Head (Write Address) Logic
	always_ff @(posedge clk) begin
		
		if (reset == 1) begin
			//reset count to 0
			count <= 0;	
			
		else	//unasserted reset
			
			if (count == DEPTH)	//FIFO is full
				IN_AXIS_TREADY <= 0;
			
			else	//FIFO has space for new data to be written
				IN_AXIS_TREADY <= 1;
				
				if (IN_AXIS_TVALID == 1) begin
					//increment count
					count = count + 1;
				end	
				
			end			 
			
		end	
		
	end
	
	//Tail (Read Address) Logic
	always_ff @(posedge clk) begin
		
		if (reset == 1) begin
			//reset output FIFO data to all 0s
			OUT_AXIS_TDATA <= {OUTW{1'b0}};	//OUTW bits wide	
			
		else	//unasserted reset
			
			if (count == 0)	//FIFO is empty
				OUT_AXIS_TVALID <= 0;
			
			else	//FIFO is not empty; output is valid
				OUT_AXIS_TVALID <= 1;
				
				if (OUT_AXIS_TREADY == 1) begin	 
					//increment count
					count = count + 1;
				end	
				
			end			 
			
		end	
		
	end	
	
	//Capacity Logic
	always_ff @(posedge clk) begin
		
		if (reset == 1) begin
			//reset output FIFO data to all 0s
			OUT_AXIS_TDATA <= {OUTW{1'b0}};	//OUTW bits wide	
			
		else	//unasserted reset
			
			
		end	
		
	end
	
endmodule	
