//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Input Memory Module

module input_mems #(
		parameter INW = 24,	//Size of data
		parameter R = 9,	//Number of rows in of input matrix X, where R >= 3
		parameter C = 8,	//Number of columns of input matrix X, where C >= 3
		parameter MAXK = 4,	//maximum value of K allowed by system	
		localparam K_BITS = $clog2(MAXK+1),
		localparam X_ADDR_BITS = $clog2(R*C),
		localparam W_ADDR_BITS = $clog2(MAXK*MAXK)
	)(
		input clk, reset,	//System clock & reset
	
		//AXIS input interface for X, W, and B
		input [INW-1:0] AXIS_TDATA,	//input data
		input AXIS_TVALID,
		input [K_BITS:0] AXIS_TUSER, //bits $clog2(MAXK+1):1 provide value of K while W[0][0] is being loaded, bit 0 is a control bit for the matrix to be represented 
		output logic AXIS_TREADY,
		
		//AXIS output interface signals and values
		output logic inputs_loaded,	//inputs_loaded = 1 when the module's internal memories hold complete X and W matrices and correct & valid values of K and B
		input compute_finished,		//used to indicate when the system is finished computing the convolution on the matrices stored in memory
		output logic [K_BITS-1:0] K,	//'K' value of weight matrix W currently stored in memory, such that 2 <= K <= MAXK
		output logic signed [INW-1:0] B,	//convolution bias value
		
		//AXIS output interface to read data from the X memory 
		input [X_ADDR_BITS-1:0] X_read_addr,
		output logic signed [INW-1:0] X_data,
		
		//AXIS output interface to read data from the W memory
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

	// Memory signals | Connect memory data inputs and outputs
	// Probably shouldn't use these, just load into memory
/*
	logic [INW-1:0] x_mem_data_in, w_mem_data_in;
	assign x_mem_data_in = AXIS_TDATA;
	assign w_mem_data_in = AXIS_TDATA;
	logic [INW-1:0] x_mem_data_out, w_mem_data_out;
	assign X_data = x_mem_data_out;
	assign W_data = w_mem_data_out;
*/	
	// Tells if first data transfer in IDLE state
	logic first_cycle;
	
	logic [X_ADDR_BITS-1:0] x_mem_addr;	
	logic [W_ADDR_BITS-1:0] w_mem_addr;
	logic x_mem_write_en, w_mem_write_en;

	assign inputs_loaded = (current_state == INPUTS_LOADED);

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
			first_cycle <= 1;
		end else begin
			case (current_state)
				IDLE: begin
					// Reset counters and first_cycle flag when returning to IDLE
					w_write_address_counter <= 0;
					x_write_address_counter <= 0;
					first_cycle <= 1;

					// load K register
					if (data_received && first_cycle) begin
						first_cycle <= 0;
						if (new_W) begin
							K_reg <= TUSER_K;
						end
						// If new_W = 0, we are not updating W, so K_reg remains unchanged
					end
				end
				INPUT_W: begin
					if (data_received) begin
						// Incremenet the counter for the W memory address on each valid transfer
						if (w_write_address_counter < K_reg * K_reg - 1) begin
							w_write_address_counter <= w_write_address_counter + 1;
						end else begin
							w_write_address_counter <= 0;
						end
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
						if (x_write_address_counter < R * C - 1) begin
							x_write_address_counter <= x_write_address_counter + 1;
						end else begin
							x_write_address_counter <= 0;
						end
					end
				end
				default: begin
					// If we are in the IDLE state, we are going to reset the counters
					w_write_address_counter <= 0;
					x_write_address_counter <= 0;
					first_cycle <= 1;
				end
			endcase
		end
	end
	
	// Choosing which address to use for memory write operations
	always_comb begin
		if (inputs_loaded) begin
			// During computation, external address control reads
			x_mem_addr = X_read_addr;
			w_mem_addr = W_read_addr;
		end else begin
			// During loading, the internal counters control writes
			x_mem_addr = x_write_address_counter;
			w_mem_addr = w_write_address_counter;
		end
	end

	always_comb begin
		case (current_state)
			IDLE, INPUT_W, INPUT_B, INPUT_X: begin
				AXIS_TREADY = 1;	// System is ready to receive new inputs
			end
			INPUTS_LOADED: begin
				AXIS_TREADY = 0;	// System is not ready to receive new inputs
			end
			default: begin
				AXIS_TREADY = 0;
			end
		endcase
	end

	// Memory write enable 
	always_comb begin
		if (data_received) begin
			case (current_state)
			// have to take into account the idle state
				INPUT_W: w_mem_write_en = 1;
				INPUT_X: x_mem_write_en = 1;
				default: begin
					w_mem_write_en = 0;
					x_mem_write_en = 0;
				end
			endcase
		end else begin
			w_mem_write_en = 0;
			x_mem_write_en = 0;
		end
	end
	
	// ----------------------------------------------------
	// FSM logic for the operations of each phase
	// ----------------------------------------------------
/*
	//FSM output logic
	always_comb begin

		// --------------------------------------------
		// IDLE Phase: No data received
		// --------------------------------------------

		if (current_state == IDLE) begin
			w_mem_data_in = '0;
			x_mem_data_in = '0;
			AXIS_TREADY = 1;	//system is ready to receive new inputs

		// --------------------------------------------
		// Phase 1: Input W Matrix
		// --------------------------------------------
		// Notes: 	Take in W matrix via AXIS
		// 			Stored in W memory
		//			Store K during 1st cycle of stage
		//			Phase complete AFTER entire W matrix is loaded (K*K values)
		//			Skipped if new_W == 0; jump to "Input X Matrix" (phase 3)
		// --------------------------------------------

		end else if (current_state == INPUT_W) begin
			//only executes if new_W = 1; input data represents first value of W matrix	

			K = K_reg;	//output K comes from K register

			//load W matrix into W memory
			for (int i = 0; i < K_reg * K_reg; i++) begin
				w_mem_data_out = w_mem_data_in;
			end	
			//Note: if new_W = 0, the input data will instead represent the first value of the X matrix, 
			//and the old W matrix will be used

		// --------------------------------------------
		// Phase 2: Input B (Bias)
		// --------------------------------------------	

		end else if (current_state == INPUT_B) begin
			B = B_reg;	//output B comes from B register

		// --------------------------------------------
		// Phase 3: Input X Matrix
		// --------------------------------------------

		end else if (current_state == INPUT_X) begin	
			//load X matrix into X memory
			for (int i = 0; i < R*C; i++) begin
				x_mem_data_out = x_mem_data_in;
			end

		// --------------------------------------------
		// Phase 4: Inputs Loaded
		// --------------------------------------------

		end else if (current_state == INPUTS_LOADED) begin	
			if (compute_finished == 1) begin
				//exit phase and reset inputs_loaded to 0, go back to beginning, waiting for new input data
				inputs_loaded = 0;
				
			end else begin
				inputs_loaded = 1;	//will remain 1 while in this phase
				AXIS_TREADY = 0;	//system is not ready to receive new inputs

				//Read data from each memory read interface based on the read addresses
				for (int i = 0; i < w_write_address_counter; i++) begin
					for (int j = 0; j < w_write_address_counter; j++) begin
						w_mem_data_out = W[i][j];
					end	
				end	

				for (int i = 0; i < x_write_address_counter; i++) begin
					for (int j = 0; j < x_write_address_counter; j++) begin
						x_mem_data_out = X[i][j];
					end	
				end
				
			end	
		end	

	end	
*/
	// FSM next state logic
	always_comb begin
		next_state = current_state;

		AXIS_TREADY = 0;
		x_mem_write_en = 0;
		w_mem_write_en = 0;
		x_mem_addr = x_write_address_counter;
		w_mem_addr = w_write_address_counter;

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
				if (data_received == 0)
					//stays in IDLE state if system has not yet received data that is ready to be inputted into a matrix;
					next_state = IDLE;
				else if (new_W == 1)
					//moves to INPUT_W state when system has received data and new_W = 1 (update W matrix)
					next_state = INPUT_W;
				else
					//moves to INPUT_X state if system has received data and new_W = 0 (old W matrix is being used)
					next_state = INPUT_X;			    
			end
			INPUT_W: begin
				AXIS_TREADY = 1;	//system is ready to receive new inputs
				if (data_received) begin
					w_mem_write_en = 1;
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
					if (x_write_address_counter == R * C - 1) begin
						next_state = INPUTS_LOADED;
					end
				end
			end
			INPUTS_LOADED: begin
				AXIS_TREADY = 0;	//system is not ready to receive new inputs
				if (compute_finished) begin
					// next_state = IDLE;? and then get rid of else statement
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
