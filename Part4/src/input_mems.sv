//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Input Memory Module

module input_mems #(
		parameter INW = 10,
		parameter R = 15,
		parameter C = 13,
		parameter MAXK = 7,
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

	// --------------------------------------------
	// Internal signals and values
	// --------------------------------------------

	// Get TUSER signals from AXIS_TUSER
	logic new_W;
	assign new_W = AXIS_TUSER[0]; 
	logic [K_BITS-1:0] TUSER_K;		// K_BITS = $clog2(MAXK+1),
	assign TUSER_K = AXIS_TUSER[K_BITS:1];
	
	// Registers for K and B | Connect K and B outputs
	logic [K_BITS-1:0] K_reg;
	logic signed [INW-1:0] B_reg;
	assign K = K_reg;
	assign B = B_reg;

	//Signal to indicate data is received (valid and ready signals are both asserted)
	logic data_received;
	assign data_received = AXIS_TVALID & AXIS_TREADY;

	// Counters for position in matrices
	logic [W_ADDR_BITS-1:0] w_write_address_counter;	// W_ADDR_BITS = $clog2(MAXK*MAXK)
	logic [X_ADDR_BITS-1:0] x_write_address_counter;	// X_ADDR_BITS = $clog2(R*C)
	
	// Where to write in memory
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

	assign inputs_loaded = (current_state == INPUTS_LOADED);

	// Instantiate X memory
	memory #(INW, R*C) X_mem_inst(.data_in(AXIS_TDATA), .data_out(X_data), .addr(x_mem_addr), .clk(clk), .wr_en(x_mem_write_en));

	// Instantiate W memory
	memory #(INW, MAXK*MAXK) W_mem_inst(.data_in(AXIS_TDATA), .data_out(W_data), .addr(w_mem_addr), .clk(clk), .wr_en(w_mem_write_en));

	// ----------------------------------------------------
	// Counter and register logic
	// ----------------------------------------------------
	always_ff @(posedge clk) begin
		if (reset) begin
			w_write_address_counter <= 0;
			x_write_address_counter <= 0;
			K_reg <= 0;
			B_reg <= 0;
		end else begin
			case (current_state)
				IDLE: begin
					// Load K register and handle first W or X element
					if (data_received && new_W) begin //first_cycle) begin
						K_reg <= TUSER_K;
						// Start W counter at 1 since we're writing W[0] in IDLE
						w_write_address_counter <= 1;
					end else if (data_received && !new_W) begin
						x_write_address_counter <= 1;
					end
				end
				INPUT_W: begin
					if (data_received) begin
						// Increment the counter for the W memory address on each valid transfer
						w_write_address_counter <= w_write_address_counter + 1;
					end
				end
				INPUT_B: begin
					if (data_received) begin
						B_reg <= AXIS_TDATA;
					end
				end
				INPUT_X: begin
					// Increment the counter for the X memory address on each valid transfer
					if (data_received) begin
						x_write_address_counter <= x_write_address_counter + 1;
					end
				end
				INPUTS_LOADED: begin
					if(compute_finished) begin
						w_write_address_counter <= 0;
						x_write_address_counter <= 0;
					end
				end
			endcase
		end
	end

	// FSM next state logic
	always_comb begin
		next_state = current_state;
		AXIS_TREADY = 0;
		x_mem_write_en = 0;
		w_mem_write_en = 0;

		// Memory address multiplexing
		if (inputs_loaded) begin
			x_mem_addr = X_read_addr;
			w_mem_addr = W_read_addr;
		end else begin
			x_mem_addr = x_write_address_counter;
			w_mem_addr = w_write_address_counter;
		end

		case (current_state)		  
			IDLE: begin
				AXIS_TREADY = 1;	//system is ready to receive new inputs
				if (data_received == 0) begin
					//stays in IDLE state if system has not yet received data
					next_state = IDLE;
				end else if (new_W == 1) begin
					//moves to INPUT_W state and writes W[0]
					w_mem_write_en = 1;
					next_state = INPUT_W;
				end else begin
					//moves to INPUT_X state and writes X[0]
					x_mem_write_en = 1;
					next_state = INPUT_X;
				end
			end
			INPUT_W: begin
				AXIS_TREADY = 1;	//system is ready to receive new inputs
				if (data_received) begin
					w_mem_write_en = 1;
					// Transition after writing the last W element
					// Counter will be at K²-1 when we write the last element
					if (w_write_address_counter == K_reg * K_reg - 1) begin
						next_state = INPUT_B;
					end
				end
			end
			INPUT_B: begin
				AXIS_TREADY = 1;	//system is ready to receive new inputs
				if (data_received) begin
					next_state = INPUT_X;
				end
			end
			INPUT_X: begin
				AXIS_TREADY = 1;	//system is ready to receive new inputs
				if (data_received) begin
					x_mem_write_en = 1;
					// Transition after writing the last X element
					// Counter will be at R*C-1 when we write the last element
					if (x_write_address_counter == R * C - 1) begin
						next_state = INPUTS_LOADED;
					end
				end
			end
			INPUTS_LOADED: begin
				AXIS_TREADY = 0;	//system is not ready to receive new inputs
				if (compute_finished) begin
					next_state = IDLE;
				end
			end
			default: begin
				AXIS_TREADY = 0;
				next_state = IDLE;
			end
		endcase
	end

	//FSM state register
	always_ff @(posedge clk) begin
		if (reset == 1)
			//reset to IDLE phase
			current_state <= IDLE;
		else
			//continue to next state specified in combinational next state logic
			current_state <= next_state;
	end	
endmodule	