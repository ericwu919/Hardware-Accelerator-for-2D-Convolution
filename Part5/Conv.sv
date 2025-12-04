// Partners: Eric Wu, Cody Chen
// Project (Part 5): Hardware Accelerator for 2D Convolution (Optimization)

module Conv #(
    parameter INW = 24,
    parameter R = 16,
    parameter C = 17,
    parameter MAXK = 9,
    localparam OUTW = $clog2(MAXK*MAXK*(128'd1 << 2*INW-2) + (1<<(INW-1)))+1,
    localparam K_BITS = $clog2(MAXK+1)
)(
    input clk,
    input reset,
    input [INW-1:0] INPUT_TDATA,
    input INPUT_TVALID,
    input [K_BITS:0] INPUT_TUSER,
    output INPUT_TREADY,
    output [OUTW-1:0] OUTPUT_TDATA,
    output OUTPUT_TVALID,
    input OUTPUT_TREADY
);

// --------------------------------------------
// Local params
// --------------------------------------------
localparam X_ADDR_BITS = $clog2(R*C);
localparam W_ADDR_BITS = $clog2(MAXK*MAXK);
localparam FIFO_DEPTH = C - 1;

// --------------------------------------------
// Internal signals and values
// --------------------------------------------

// Signals FROM input memory module
logic inputs_loaded;    // Assert whe nX, W, K, and B loaded and ready
logic [K_BITS-1:0] K;
logic signed [INW-1:0] B;

logic signed [INW-1:0] X_data_0, X_data_1, X_data_2, X_data_3;
logic signed [INW-1:0] W_data_0, W_data_1, W_data_2, W_data_3;

// Signals TO input memory module
logic compute_finished;     // Control signal (sent to input_mems when convolution complete)
logic [X_ADDR_BITS-1:0] X_read_addr_0, X_read_addr_1, X_read_addr_2, X_read_addr_3;
logic [W_ADDR_BITS-1:0] W_read_addr_0, W_read_addr_1, W_read_addr_2, W_read_addr_3;

// MAC Control Signals
logic signed [INW-1:0] mac_init_value_0, mac_init_value_1, mac_init_value_2, mac_init_value_3;
logic signed [OUTW-1:0] mac_out_0, mac_out_1, mac_out_2, mac_out_3;
logic mac_init_acc_0, mac_init_acc_1, mac_init_acc_2, mac_init_acc_3; // 1: initialize accumulator
logic mac_input_valid_0, mac_input_valid_1, mac_input_valid_2, mac_input_valid_3;  // 1: MAC processes current inputs

// Signals FOR Output FIFO
logic fifo_in_valid;    // 1 when write to FIFO
logic fifo_in_ready;    // 1 by FIFO when can accept data
logic signed [OUTW-1:0] fifo_in_data;

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

// output write control
logic [1:0] output_write_idx;   // which mac output to write (0-3)
logic [2:0] num_valid_outputs;  // how many MACs have valid outputs (0-4)

// --------------------------------------------
// FSM States
// --------------------------------------------
typedef enum logic [3:0] {  
    IDLE,
    SETUP_ADDR,
    INIT_ACC,
    COMPUTE_MAC,
    WAIT_MAC_1,
    WAIT_MAC_2,
    WAIT_MAC_3,
    WAIT_MAC_4,
    WRITE_OUTPUT,
    DONE
} state_t;
state_t current_state, next_state;

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
    // Calculate W address: W[i][j] in row-major order = i*K+j
    //if (c_counter < C_out) begin
        X_read_addr_0 = (r_counter + i_counter) * C + (c_counter + j_counter);
        W_read_addr_0 = i_counter * K + j_counter;
    /*end else begin
        X_read_addr_0 = 0;
        W_read_addr_0 = 0;
    end*/

    //if (c_counter + 1 < C_out) begin
        X_read_addr_1 = (r_counter + i_counter) * C + (c_counter + 1 + j_counter);
        W_read_addr_1 = i_counter * K + j_counter;
    /*end else begin
        X_read_addr_1 = 0;
        W_read_addr_1 = 0;
    end*/

    //if (c_counter + 2 < C_out) begin
        X_read_addr_2 = (r_counter + i_counter) * C + (c_counter + 2 + j_counter);
        W_read_addr_2 = i_counter * K + j_counter;
    /*end else begin
        X_read_addr_2 = 0;
        W_read_addr_2 = 0;
    end*/

    //if (c_counter + 3 < C_out) begin
        X_read_addr_3 = (r_counter + i_counter) * C + (c_counter + 3 + j_counter);
        W_read_addr_3 = i_counter * K + j_counter;
    /*end else begin
        X_read_addr_3 = 0;
        W_read_addr_3 = 0;
    end*/
    
end

// determine # of valid outputs this iteration
always_comb begin
    if (c_counter + 4 <= C_out) begin
        num_valid_outputs = 4;
    end else if (c_counter + 3 <= C_out) begin
        num_valid_outputs = 3;
    end else if (c_counter + 2 <= C_out) begin
        num_valid_outputs = 2;
    end else if (c_counter + 1 <= C_out) begin
        num_valid_outputs = 1;
    end else begin
        num_valid_outputs = 1;
    end
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
        output_write_idx <= 0;
    end else begin
        case (current_state)
            IDLE: begin
                // Reset the counters when starting new computation
                r_counter <= 0;
                c_counter <= 0;
                i_counter <= 0;
                j_counter <= 0;
                mac_count <= 0;
                output_write_idx <= 0;
            end
            SETUP_ADDR: begin
                // set up address for [0][0]
                i_counter <= 0;
                j_counter <= 0;
                mac_count <= 0;
                output_write_idx <= 0;
            end
            INIT_ACC: begin
                // initialize accumulator, prepare first address [0][0]
                // we don't increment yet, we start feeding in COMPUTE_MAC
                i_counter <= 0;
                j_counter <= 0;
            end
            COMPUTE_MAC: begin
                // after feeding current data, increment for next
                if (j_counter == K - 1) begin
                    j_counter <= 0;
                    i_counter <= i_counter + 1;
                end else begin
                    j_counter <= j_counter + 1;
                end
                mac_count <= mac_count + 1;
            end
            WRITE_OUTPUT: begin
                if (fifo_in_ready) begin
                    if (output_write_idx == num_valid_outputs - 1) begin
                        output_write_idx <= 0;
                        i_counter <= 0;
                        j_counter <= 0;
                        mac_count <= 0;

                        if (c_counter + 4 >= C_out) begin
                            c_counter <= 0;
                            if (r_counter == R_out - 1) begin
                                r_counter <= 0;
                            end else begin
                                r_counter <= r_counter + 1;
                            end
                        end else begin
                            c_counter <= c_counter + 4;
                        end
                    end else begin
                        output_write_idx <= output_write_idx + 1;
                    end
                end
            end
        endcase
    end
end

// --------------------------------------------
// FSM Control Logic
// --------------------------------------------
always_comb begin
    next_state = current_state;
    mac_init_acc_0 = 0;
    mac_input_valid_0 = 0;
    mac_init_value_0 = B;

    mac_init_acc_1 = 0;
    mac_input_valid_1 = 0;
    mac_init_value_1 = B;

    mac_init_acc_2 = 0;
    mac_input_valid_2 = 0;
    mac_init_value_2 = B;

    mac_init_acc_3 = 0;
    mac_input_valid_3 = 0;
    mac_init_value_3 = B;

    fifo_in_valid = 0;
    fifo_in_data = 0;
    compute_finished = 0;

    case (current_state)
        IDLE: begin
            if (inputs_loaded) begin
                next_state = SETUP_ADDR;
            end
        end
        SETUP_ADDR: begin
            // wait one cycle for memory
            next_state = INIT_ACC;
        end
        INIT_ACC: begin
            // initialize accumulator with B only
            if (c_counter < C_out) begin
                mac_init_acc_0 = 1;
                mac_init_value_0 = B;
            end
            if (c_counter + 1< C_out) begin
                mac_init_acc_1 = 1;
                mac_init_value_1 = B;
            end
            if (c_counter + 2 < C_out) begin
                mac_init_acc_2 = 1;
                mac_init_value_2 = B;
            end
            if (c_counter + 3 < C_out) begin
                mac_init_acc_3 = 1;
                mac_init_value_3 = B;
            end
            next_state = COMPUTE_MAC;
        end
        COMPUTE_MAC: begin
            // feed data to MAC
            if (c_counter < C_out) begin
                mac_input_valid_0 = 1;
            end
            if (c_counter + 1 < C_out) begin
                mac_input_valid_1 = 1;
            end
            if (c_counter + 2 < C_out) begin
                mac_input_valid_2 = 1;
            end
            if (c_counter + 3 < C_out) begin
                mac_input_valid_3 = 1;
            end
            
            if (mac_count == K_squared - 1) begin
                // fed all K*K pairs, now wait 4 cycles for pipeline
                next_state = WAIT_MAC_1;
            end
        end
        WAIT_MAC_1: begin
            next_state = WAIT_MAC_2;
        end
        WAIT_MAC_2: begin
            next_state = WAIT_MAC_3;
        end
        WAIT_MAC_3: begin
            next_state = WAIT_MAC_4;
        end
        WAIT_MAC_4: begin
            next_state = WRITE_OUTPUT;
        end
        WRITE_OUTPUT: begin
            fifo_in_valid = 1;

            case (output_write_idx)
                2'd0: fifo_in_data = mac_out_0;
                2'd1: fifo_in_data = mac_out_1;
                2'd2: fifo_in_data = mac_out_2;
                2'd3: fifo_in_data = mac_out_3;    
                default: fifo_in_data = mac_out_0;
            endcase

            if (fifo_in_ready) begin
                if (output_write_idx >= num_valid_outputs - 1) begin
                    if (r_counter == R_out - 1 && c_counter + 4 >= C_out) begin
                        next_state = DONE;
                    end else begin
                        next_state = SETUP_ADDR;
                    end
                end else begin
                    next_state = WRITE_OUTPUT;
                end
            end else begin
                next_state = WRITE_OUTPUT;
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
    .X_read_addr_0(X_read_addr_0),
    .X_data_0(X_data_0),
    .W_read_addr_0(W_read_addr_0),
    .W_data_0(W_data_0),

    .X_read_addr_1(X_read_addr_1),
    .X_data_1(X_data_1),
    .W_read_addr_1(W_read_addr_1),
    .W_data_1(W_data_1),
    
    .X_read_addr_2(X_read_addr_2),
    .X_data_2(X_data_2),
    .W_read_addr_2(W_read_addr_2),
    .W_data_2(W_data_2),
    
    .X_read_addr_3(X_read_addr_3),
    .X_data_3(X_data_3),
    .W_read_addr_3(W_read_addr_3),
    .W_data_3(W_data_3)
);

// MAC Pipeline Module
mac_pipe #(
    .INW(INW),
    .OUTW(OUTW)
) mac_inst_0 (
    .clk(clk),
    .reset(reset),
    .input0(X_data_0),
    .input1(W_data_0),
    .init_value(mac_init_value_0),
    .out(mac_out_0),
    .init_acc(mac_init_acc_0),
    .input_valid(mac_input_valid_0)
);

mac_pipe #(
    .INW(INW),
    .OUTW(OUTW)
) mac_inst_1 (
    .clk(clk),
    .reset(reset),
    .input0(X_data_1),
    .input1(W_data_1),
    .init_value(mac_init_value_1),
    .out(mac_out_1),
    .init_acc(mac_init_acc_1),
    .input_valid(mac_input_valid_1)
);

mac_pipe #(
    .INW(INW),
    .OUTW(OUTW)
) mac_inst_2 (
    .clk(clk),
    .reset(reset),
    .input0(X_data_2),
    .input1(W_data_2),
    .init_value(mac_init_value_2),
    .out(mac_out_2),
    .init_acc(mac_init_acc_2),
    .input_valid(mac_input_valid_2)
);

mac_pipe #(
    .INW(INW),
    .OUTW(OUTW)
) mac_inst_3 (
    .clk(clk),
    .reset(reset),
    .input0(X_data_3),
    .input1(W_data_3),
    .init_value(mac_init_value_3),
    .out(mac_out_3),
    .init_acc(mac_init_acc_3),
    .input_valid(mac_input_valid_3)
);

// Output FIFO Module
fifo_out #(
    .OUTW(OUTW),
    .DEPTH(FIFO_DEPTH)
) output_fifo_inst (
    .clk(clk),
    .reset(reset),
    .IN_AXIS_TDATA(fifo_in_data),
    .IN_AXIS_TVALID(fifo_in_valid),
    .IN_AXIS_TREADY(fifo_in_ready),
    .OUT_AXIS_TDATA(OUTPUT_TDATA),
    .OUT_AXIS_TVALID(OUTPUT_TVALID),
    .OUT_AXIS_TREADY(OUTPUT_TREADY)
);

endmodule
