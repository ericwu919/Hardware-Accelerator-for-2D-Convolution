//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Input Memory Module

module input_mems #(
		parameter INW = 24,
		parameter R = 9,
		parameter C = 8,
		parameter MAXK = 4,
		localparam K_BITS = $clog2(MAXK+1),
		localparam X_ADDR_BITS = $clog2(R*C),
		localparam W_ADDR_BITS = $clog2(MAXK*MAXK)
	)(
		input clk, reset,
		input [INW-1:0] AXIS_TDATA,
		input AXIS_TVALID,
		input [K_BITS:0] AXIS_TUSER,
		output logic AXIS_TREADY,
		output logic inputs_loaded,
		input compute_finished,
		output logic [K_BITS-1:0] K,
		output logic signed [INW-1:0] B,
		input [X_ADDR_BITS-1:0] X_read_addr,
		output logic signed [INW-1:0] X_data,
		input [W_ADDR_BITS-1:0] W_read_addr,
		output logic signed [INW-1:0] W_data
	);	
	
	
endmodule	
