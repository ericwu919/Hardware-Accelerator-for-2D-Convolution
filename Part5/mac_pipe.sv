//Partners: Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Pipelined Design for the MAC Unit

module mac_pipe #(
        parameter INW = 24,
        parameter OUTW = 48
    )(
        input signed [INW-1:0] input0, input1, init_value,
        output logic signed [OUTW-1:0] out,
        input clk, reset, init_acc, input_valid 
    );

    // Pipelined multiplier output (4 stages internal)
    logic signed [2*INW-1:0] prod;
    
    // Delayed enable signals to match pipeline depth (4 cycles)
    logic [3:0] enable_pipe;
    
    logic signed [OUTW-1:0] sum;

    // Instantiate 4-stage pipelined multiplier
    DW02_mult_4_stage #(.A_width(INW), .B_width(INW)) 
        pipelined_mult (
            .A(input0),
            .B(input1),
            .TC(1'b1),  
            .CLK(clk),
            .PRODUCT(prod)
        );

    // Pipeline the input_valid signal to match multiplier latency (4 cycles)
    always_ff @(posedge clk) begin
        if (reset) begin
            enable_pipe <= 4'b0;
        end else begin
            enable_pipe <= {enable_pipe[2:0], input_valid};
        end
    end
    
    always_comb begin
        // Add the result of the multiplier (prod) to the flip-flop output
        sum = prod + out;
    end

    // init_acc happens immediately (no delay) to initialize the accumulator
    // enable happens after 4 cycles to account for multiplier pipeline
    always_ff @(posedge clk) begin : accumulator_register
        if (reset) 
            out <= 0;
        else if (init_acc == 1)  // Initialize immediately
            out <= init_value;
        else if (enable_pipe[3] == 1)  // Accumulate after 4-cycle delay
            out <= sum;
    end 


endmodule
