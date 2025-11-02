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

	//Internal Matrices for holding data
	// I don't think we should use 2D array, but also the dimension is wrong
	// for W it should be [MAXK-1:0][MAXK-1:0]
	// the reason why i say that is because the memory module won't be able to see these
	logic [INW-1:0] W[C-1:0][K_BITS-1:0];
	logic [INW-1:0] X[R-1:0][K_BITS-1:0];

	// Counters for position in matrices
	logic [W_ADDR_BITS-1:0] w_write_address_counter;	// W_ADDR_BITS = $clog2(MAXK*MAXK)
	logic [X_ADDR_BITS-1:0] x_write_address_counter;	// X_ADDR_BITS = $clog2(R*C)

	// Memory signals | Connect memory data inputs and outputs
	// Probably shouldn't use these, just load into memory
	logic [INW-1:0] x_mem_data_in, w_mem_data_in;
	assign x_mem_data_in = AXIS_TDATA;
	assign w_mem_data_in = AXIS_TDATA;
	logic [INW-1:0] x_mem_data_out, w_mem_data_out;
	assign X_data = x_mem_data_out;
	assign W_data = w_mem_data_out;

	// Tells if first data transfer in IDLE state
	logic first_cycle;

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
	// might need to change to x_mem_addr for .addr
	memory #(INW, R*C) X_mem_inst(.data_in(x_mem_data_in), .data_out(x_mem_data_out), .addr(X_read_addr), .clk(clk), .wr_en(x_mem_write_en));

	// Instantiate W memory
	// might need to change to w_mem_addr for .addr
	memory #(INW, MAXK*MAXK) W_mem_inst(.data_in(w_mem_data_in), .data_out(w_mem_data_out), .addr(W_read_addr), .clk(clk), .wr_en(w_mem_write_en));
	
	/*
	// --------------------------------------------
	// Phase 1: Input W Matrix
	// --------------------------------------------
	// Notes: 	Take in W matrix via AXIS
	// 			Stored in W memory
	//			Store K during 1st cycle of stage
	//			Phase complete AFTER entire W matrix is loaded (K*K values)
	//			Skipped if new_W == 0; jump to "Input X Matrix" (phase 3)
	// --------------------------------------------
	
	// W counter logic
	// W memory write enable logic
	always_ff @(posedge clk) begin
		if (reset) begin
			w_mem_write_en <= 0;
		end else begin
			w_mem_write_en <= (current_state == input_W) && (data_received == 1);
		end
	end

	// W memory address logic
	always_ff @(posedge clk) begin
		if (reset) begin
			w_mem_addr <= 0;
		end else begin
			
		end
	end


	// K register logic (get K on first cycle of stage)
	always_ff @(posedge clk) begin
		if (reset) 
			//reset the W matrix data to all 0s
			w_mem_data_in <= '0;
		else if (new_W == 0)
			//exit this phase and go to Phase 3: Input X Matrix
			next_state = INPUT_X;
		else

	end
	*/
	
	// ----------------------------------------------------
	// FSM Output Logic for determining operation of phase changes
	// ----------------------------------------------------

	// Control for AXIS_TREADY
	always_comb begin
		case (current_state)
			IDLE: AXIS_TREADY = 1;	//ready to receive new inputs
			INPUT_W: AXIS_TREADY = 1;	//ready to receive W matrix inputs
			INPUT_B: AXIS_TREADY = 1;	//ready to receive B input
			INPUT_X: AXIS_TREADY = 1;	//ready to receive X matrix inputs
			INPUTS_LOADED: AXIS_TREADY = 0;	//not ready to receive new inputs
			default: AXIS_TREADY = 0;
		endcase
	end

	// Choosing which address to use for memory write operations
	always_comb begin
		if (inputs_loaded) begin
			// During computation, external address control reads
			x_mem_addr = X_read_addr;
			w_mem_addr = W_read_addr;
		end else begin
			// DUring loading, the internal countrers control writes
			x_mem_addr = x_write_address_counter;
			w_mem_addr = w_write_address_counter;
		end
	end

	// Memory write enable 
	always_comb begin
		if (data_received) begin
			case (current_state)
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

	always_ff @(posedge clk) begin
		if (reset) begin
			w_write_address_counter <= 0;
			x_write_address_counter <= 0;
		end else begin
			case (current_state)
				IDLE: begin
					w_write_address_counter <= 0;
					x_write_address_counter <= 0;
					
					if (data_received && first_cycle) begin
						firsrt_cycle <= 0;
						if (new_W) begin
							K_reg <= TUSER_K;	//store K value
						end
					end else if (!data_received) begin
						//stay in IDLE state
						first_cycle <= 1;
					end
				end
				INPUT_W: begin
					if (data_received
			endcase
		end
	end

	//FSM output logic
	always_comb begin

		// --------------------------------------------
		// IDLE Phase: No data received
		// --------------------------------------------

		if (current_state == IDLE) begin
			w_mem_data_in = '0;
			x_mem_data_in = '0;
			// I moved this all into its own always_comb so its easier to read
			// AXIS_TREADY = 1;	//system is ready to receive new inputs

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
			//input data represents first value of W matrix if new_W = 1
			if (new_W == 1) begin	
				K_reg = TUSER_K;	//store value of K

				//load W matrix
				for (int i = 0; i < K_reg; i++) begin
					for (int j = 0; j < K_reg; j++) begin
						W[i][j] = w_mem_data_in;
					end	
				end

			end	
			//Note: if new_W = 0, the input data will instead represent the first value of the X matrix, 
			//and the old W matrix will be used

		// --------------------------------------------
		// Phase 2: Input B (Bias)
		// --------------------------------------------	

		end else if (current_state == INPUT_B) begin
			B_reg = AXIS_TDATA;		//store scalar data value from AXI-Stream input interface into B register

		// --------------------------------------------
		// Phase 3: Input X Matrix
		// --------------------------------------------

		end else if (current_state == INPUT_X) begin	
			//load X matrix
			for (int i = 0; i < R; i++) begin
				for (int j = 0; j < C; j++) begin
					X[i][j] = x_mem_data_in;
				end	
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

	// FSM next state logic (I think we shuold rewrite this part (i wrote some things above))
	always_comb begin
		if (current_state == IDLE)
			//moves to INPUT_W state when system has received data that is ready to be inputted into a matrix;
			//otherwise, it stays in IDLE state
			// Do we need to check new_W here?
			next_state = (data_received == 0) ? IDLE : INPUT_W; // If we use this, I think the logic is wrong b/c of new_W==0 (this one doesn't take that into account, which skips INPUT_W)

		else if (current_state == INPUT_W)
			next_state = (new_W == 0) ? INPUT_X : INPUT_B;
		else if (current_state == INPUT_B)
			next_state = INPUT_X;
		else if (current_state == INPUT_X)
			next_state = INPUTS_LOADED;
		else if (current_state == INPUTS_LOADED)
			next_state = (compute_finished == 1) ? IDLE : INPUTS_LOADED;
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
