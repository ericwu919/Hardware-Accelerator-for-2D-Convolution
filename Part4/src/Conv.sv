// Partners: Eric Wu, Cody Chen
// Project: Hardware Accelerator for 2D Convolution
//Design: 2D Convolution With Bias

module Conv #(
    parameter INW = 24, //number of bits for each input data word
    parameter R = 16,    //number of rows in the X matrix
    parameter C = 17,    //number of columns in the X matrix
    parameter MAXK = 9, // maximum value of K (rows and columns of W) that is supported
    localparam OUTW = $clog2(MAXK*MAXK*(128'd1 << 2*INW-2) + (1<<(INW-1)))+1,   //width of output data
    localparam K_BITS = $clog2(MAXK+1)      //width of K
    )(
    //System clock and reset    
    input clk,
    input reset,

    //Convolution Module Input Interface
    input [INW-1:0] INPUT_TDATA,
    input INPUT_TVALID,
    input [K_BITS:0] INPUT_TUSER,
    output INPUT_TREADY,

    //Convolution Module Output Interface
    output [OUTW-1:0] OUTPUT_TDATA,
    output OUTPUT_TVALID,
    input OUTPUT_TREADY
    );
    
    // ============================================
    // Local Parameters
    // ============================================

    localparam X_ADDR_BITS = $clog2(R*C);   // Address width for X Memory
    localparam W_ADDR_BITS = $clog2(MAXK*MAXK); // Address width for W Memory
    localparam FIFO_DEPTH = C - 1;

    // --------------------------------------------
    // Internal signals and values
    // --------------------------------------------

    // Signals FROM input memory module
    logic inputs_loaded;    // Assert whe nX, W, K, and B loaded and ready
    logic [K_BITS-1:0] K;
    logic signed [INW-1:0] B;
    logic signed [INW-1:0] X_data, W_data;

    // Signals TO input memory module
    logic compute_finished;     // Control signal (sent to input_mems when convolution complete)
    logic [X_ADDR_BITS-1:0] X_read_addr;
    logic [W_ADDR_BITS-1:0] W_read_addr;

    // MAC Control Signals
    logic signed [INW-1:0] mac_init_value;
    logic signed [OUTW-1:0] mac_out;
    logic mac_init_acc; // 1: initialize accumulator
    logic mac_input_valid;  // 1: MAC processes current inputs

    // Signals FOR Output FIFO
    logic fifo_in_valid;    // 1 when write to FIFO
    logic fifo_in_ready;    // 1 by FIFO when can accept data

    // Output dimensions
    logic [$clog2(R+1)-1:0] R_out;  // # of output rows = R-K+1
    logic [$clog2(C+1)-1:0] C_out;  // # of output cols = C-K+1

    // --------------------------------------------
    // Counters for Convolution
    // --------------------------------------------
    logic [X_ADDR_BITS-1:0] r_counter;  // Output row counter (0 to R-K)
    logic [X_ADDR_BITS-1:0] c_counter;  // Output column counter (0 to C-K)
    logic [W_ADDR_BITS-1:0] i_counter;  // Weight row counter (0 to K-1)
    logic [W_ADDR_BITS-1:0] j_counter;  // Weight column counter (0 to K-1)

    // MAC operation tracking
    logic [W_ADDR_BITS:0] mac_count;
    logic [W_ADDR_BITS:0] K_squared;
    
    // --------------------------------------------
    // FSM States
    // --------------------------------------------
    typedef enum logic [2:0] {  
        IDLE,           // wait for inputs_loaded
        SETUP_ADDR,     // set up first address [0][0], wait for memory read
        INIT_ACC,       // init MAC accum with bias B
        COMPUTE_MAC,    // feed K*K data pairs through mac
        WAIT_MAC_1,     // first cycle waiting for MAC pipeline
        WAIT_MAC_2,     // second cycle waiting for mac pipeline to complete
        WRITE_OUTPUT,   // write MAC result to output FIFO
        DONE            // signal completion, return to IDLE
    } state_t;
    state_t current_state, next_state;

    // -------------------------------------------------------------------------------
    // Instantiations of Input Memories, Pipelined MAC, and Output FIFO modules
    // -------------------------------------------------------------------------------

    // Input Memory Module
    input_mems #(
        .INW(INW),
        .R(R),
        .C(C),
        .MAXK(MAXK)
    ) input_mem_inst (
        .clk(clk),
        .reset(reset),
        .AXIS_TDATA(INPUT_TDATA),
        .AXIS_TVALID(INPUT_TVALID),
        .AXIS_TUSER(INPUT_TUSER),
        .AXIS_TREADY(INPUT_TREADY),
        .inputs_loaded(inputs_loaded),
        .compute_finished(compute_finished),
        .K(K),
        .B(B),
        .X_read_addr(X_read_addr),
        .X_data(X_data),
        .W_read_addr(W_read_addr),
        .W_data(W_data)
    );

    // MAC Pipeline Module
    mac_pipe #(
        .INW(INW),
        .OUTW(OUTW)
    ) mac_inst (
        .clk(clk),
        .reset(reset),
        .input0(X_data),
        .input1(W_data),
        .init_value(mac_init_value),
        .out(mac_out),
        .init_acc(mac_init_acc),
        .input_valid(mac_input_valid)
    );

    // Output FIFO Module
    fifo_out #(
        .OUTW(OUTW),
        .DEPTH(FIFO_DEPTH)
    ) output_fifo_inst (
        .clk(clk),
        .reset(reset),
        .IN_AXIS_TDATA(mac_out),
        .IN_AXIS_TVALID(fifo_in_valid),
        .IN_AXIS_TREADY(fifo_in_ready),
        .OUT_AXIS_TDATA(OUTPUT_TDATA),
        .OUT_AXIS_TVALID(OUTPUT_TVALID),
        .OUT_AXIS_TREADY(OUTPUT_TREADY)
    );

    // --------------------------------------------
    // Calculate Output Dimensions
    // --------------------------------------------
    always_comb begin
        R_out = R - K + 1;
        C_out = C - K + 1;
        K_squared = K * K;  // total # of MAC ops per output element
    end

    // --------------------------------------------
    // Address Calculation
    // --------------------------------------------
    always_comb begin
        // Calculate X address: X[r+i][c+j] in row_major order = (r+i)*C + (c+j)
        X_read_addr = (r_counter + i_counter) * C + (c_counter + j_counter);
        // Calculate W address: W[i][j] in row-major order = i*K+j
        W_read_addr = i_counter * K + j_counter;
    end

    // --------------------------------------------
    // Counter Logic
    // --------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            r_counter <= 0;
            c_counter <= 0;
            i_counter <= 0;
            j_counter <= 0;
            mac_count <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    // Reset the counters when starting new computation
                    r_counter <= 0;
                    c_counter <= 0;
                    i_counter <= 0;
                    j_counter <= 0;
                    mac_count <= 0;
                end
                SETUP_ADDR: begin
                    // address [0][0] is begin set up for first read
                    // we want to ensure i,j counters are at 0 (starting pos)
                    i_counter <= 0;
                    j_counter <= 0;
                    mac_count <= 0;
                end
                INIT_ACC: begin
                    // when initializing accumulator, we want to prepare for the next address
                    // since our memory has 1-cycle read latency, we set up address for [0][1]
                    // data for [0][1] will be ready when we need it in next state COMPUTE_MAC
                    if (K > 1) begin
                        j_counter <= 1;
                    end
                    // if K==1, no increment is needed (only one element)
                end
                COMPUTE_MAC: begin
                    mac_count <= mac_count + 1;
                    
                    // Increment i,j to prep NEXT address for next cycle
                    if (mac_count < K_squared - 1) begin
                        if (j_counter == K - 1) begin
                            // when on end of row in W matrix, wrap to next row
                            j_counter <= 0;
                            i_counter <= i_counter + 1;
                        end else begin
                            // move to next col in current row
                            j_counter <= j_counter + 1;
                        end
                    end
                    // and here, if mac_count==K*K-1, we are on last MAC, so no more increment needed
                end
                WRITE_OUTPUT: begin
                    if (fifo_in_ready) begin
                        // reset i,j counters for next convolution window
                        i_counter <= 0;
                        j_counter <= 0;
                        mac_count <= 0;

                        // move to next output position in row_major order
                        if (c_counter == C_out - 1) begin
                            // end of output row, move to next row
                            c_counter <= 0;
                            if (r_counter == R_out - 1) begin
                                // last output element done
                                r_counter <= 0;
                            end else begin
                                // move to next output row
                                r_counter <= r_counter + 1;
                            end
                        end else begin
                            // move to next col in current output row
                            c_counter <= c_counter + 1;
                        end
                    end
                    // if FIFO not ready, counters stall (might not be the best... but this is what we did)
                end
            endcase
        end
    end

    // --------------------------------------------
    // FSM Control Logic
    // --------------------------------------------
    always_comb begin
        next_state = current_state;
        mac_init_acc = 0;
        mac_input_valid = 0;
        mac_init_value = B;
        fifo_in_valid = 0;
        compute_finished = 0;

        case (current_state)
            IDLE: begin
                if (inputs_loaded) begin
                    next_state = SETUP_ADDR;
                end
            end
            SETUP_ADDR: begin
                // address for X[0][0] nad W[0][0] being set up
                next_state = INIT_ACC;
            end
            INIT_ACC: begin
                // memory data for [0][0] is now valid, initialize MAC accumulator with B
                mac_init_acc = 1;
                mac_init_value = B;
                next_state = COMPUTE_MAC;
            end
            COMPUTE_MAC: begin
                mac_input_valid = 1;
                // check if last of K*K ops
                if (mac_count == K_squared - 1) begin
                    // all data has been fed to MAC, MAC pipeline needs 2 more cycles to produce final result
                    next_state = WAIT_MAC_1;
                end
            end
            WAIT_MAC_1: begin
                next_state = WAIT_MAC_2;
            end
            WAIT_MAC_2: begin
                next_state = WRITE_OUTPUT;
            end
            WRITE_OUTPUT: begin
                // now we try to write to output FIFO
                fifo_in_valid = 1;
                if (fifo_in_ready) begin
                    // there is space in FIFO and accepeted data
                    // check if last output element
                    if (r_counter == R_out - 1 && c_counter == C_out - 1) begin
                        next_state = DONE;
                    end else begin
                        // more output elements to compute
                        // go back to SETUP_ADDR to start next output element
                        next_state = SETUP_ADDR;
                    end
                end
            end
            DONE: begin
                compute_finished = 1;
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end    

    // --------------------------------------------
    // FSM State Register
    // --------------------------------------------

    always_ff @(posedge clk) begin
        if (reset) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

endmodule    
