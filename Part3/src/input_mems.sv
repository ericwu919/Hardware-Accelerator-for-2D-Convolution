//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Input Memory Module

module input_mems #(
		parameter INW = 24,	//Size of data
		parameter R = 9,	//Number of rows in of input matrix X, where R >= 3
		parameter C = 8,	//Number of columns of input matrix X, where C >= 3
		parameter MAXK = 4,	
		localparam K_BITS = $clog2(MAXK+1),
		localparam X_ADDR_BITS = $clog2(R*C),
		localparam W_ADDR_BITS = $clog2(MAXK*MAXK)
	)(
		input clk, reset,	//System clock & reset
	
		//AXIS input interface for X, W, and B
		input [INW-1:0] AXIS_TDATA,
		input AXIS_TVALID,
		input [K_BITS:0] AXIS_TUSER, //bits $clog2(MAXK+1):1 provide value of K while W[0][0] is being loaded, bit 0 is a control bit for the matrix to be represented 
		output logic AXIS_TREADY,
		
		//AXIS output interface signals and values
		output logic inputs_loaded,	//inputs_loaded = 1 when the module's internal memories hold complete X and W matrices and correct & valid values of K and B
		input compute_finished,		//used to indicate when the system is finished computing the convolution on the matrices stored in memory
		output logic [K_BITS-1:0] K,	//K value of weight matrix currently stored in memory
		output logic signed [INW-1:0] B,	//convolution bias value
		
		//AXIS output interface to read data from the X memory 
		input [X_ADDR_BITS-1:0] X_read_addr,
		output logic signed [INW-1:0] X_data,
		
		//AXIS output interface to read data from the W memory
		input [W_ADDR_BITS-1:0] W_read_addr,
		output logic signed [INW-1:0] W_data
	);
	
	// Internal signals and values
	// Get TUSER signals
	logic new_W;
	assign new_W = AXIS_TUSER[0]; 
	logic [K_BITS-1:0] TUSER_K;		// K_BITS = $clog2(MAXK+1),
	assign TUSER_K = AXIS_TUSER[K_BITS:1];
	
	// Registers for K and B | Connect K and B outputs
	logic [K_BITS-1:0] K_reg;
	logic signed [INW-1:0] B_reg;
	assign K = K_reg;
	assign B = B_reg;

	// Counters for position in matrices
	logic [W_ADDR_BITS-1:0] w_write_address_counter;	// W_ADDR_BITS = $clog2(MAXK*MAXK)
	logic [X_ADDR_BITS-1:0] x_write_address_counter;	// X_ADDR_BITS = $clog2(R*C)

	// Memory signals | Connect memory data inputs and outputs
	logic [INW-1:0] x_mem_data_in, w_mem_data_in;
	assign x_mem_data_in = AXIS_TDATA;
	assign w_mem_data_in = AXIS_TDATA;
	logic [INW-1:0] x_mem_data_out, w_mem_data_out;
	assign X_data = x_mem_data_out;
	assign W_data = w_mem_data_out;

	logic [X_ADDR_BITS-1:0] x_mem_addr;	
	logic [W_ADDR_BITS-1:0] w_mem_addr;
	logic x_mem_write_en, w_mem_write_en;

	// FSM States
	typedef enum logic [2:0] {
		IDLE,
		INPUT_W,
		INPUT_B,
		INPUT_X,
		INPUTS_LOADED
	} state_t;

	state_t current_state, next_state;

	// Instantiate X memory
	memory #(INW, R*C) X_mem_inst(.data_in(x_mem_data_in), .data_out(x_mem_data_out), .addr(X_read_addr), .clk(clk), .write_en());

	// Instantiate W memory
	memory #(INW, MAXK*MAXK) W_mem_inst(.data_in(w_mem_data_in), .data_out(w_mem_data_out), .addr(W_read_addr), .clk(clk), .write_en());
	
	// --------------------------------------------
	// Phase 1: Input W Matrix
	// --------------------------------------------
	
/* 	always_ff @(posedge clk) begin
		if (reset) begin
			//reset the W matrix data to all 0s
			w_mem_data_in <= '0;
			
		end else if (new_W == 0)
			//exit this phase and go to Phase 3: Input X Matrix
			next_state = ;
		else


		end
			
				
			
	end */
	
	// --------------------------------------------
	// Phase 2: Input B (Bias)
	// --------------------------------------------	
	
	always_ff @(posedge clk) begin
		
		B <= B_reg;
		
	end
	
	// --------------------------------------------
	// Phase 3: Input X Matrix
	// --------------------------------------------
	
	always_ff @(posedge clk) begin
		
		
		
	end
	
	// --------------------------------------------
	// Phase 4: Inputs Loaded
	// --------------------------------------------
	
	always_ff @(posedge clk) begin
		
		if (compute_finished == 1) begin
			//exit phase and reset inputs_loaded to 0
			inputs_loaded <= 0;
			
		end else begin
			inputs_loaded <= 1;	//will remain 1 while in this phase
			AXIS_TREADY <= 0;	//system is not ready to receive new inputs
			
			//Read data from each memory read interface based on the read addresses
			X_data <= [X_read_addr];
			W_data <= [W_read_addr];

		end
		
	end
	
	// ----------------------------------------------------
	// FSM logic for determining operation of phase changes
	// ----------------------------------------------------

	//FSM output logic
	always_comb begin
		if (current_state == IDLE)
			w_mem_data_in <= '0;
			x_mem_data_in <= '0;

	end	

	//FSM next state logic
	always_comb begin
		if (reset)
			next_state = IDLE;
		else if (current_state == IDLE)
			next_state = (reset == 1) ? IDLE : INPUT_W; 
		else if (current_state == INPUT_W)
			next_state = (new_W == 0) ? INPUT_X : INPUT_B;
		else if (current_state == INPUT_B)
			next_state = INPUT_X;
		else if (current_state == INPUT_X)
			next_state = INPUTS_LOADED;
		else if (current_state == INPUTS_LOADED)
			next_state = IDLE;					

	end

	//FSM state register
	always_ff @(posedge clk) begin
		if (reset == 1)
			//reset to Phase 1: Input W Matrix
			current_state <= INPUT_W;

		else
			//continue to next state specified in combinational next state logic
			current_state <= next_state;
	end	

endmodule	
