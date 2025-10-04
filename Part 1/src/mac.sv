//Eric Wu, Cody Chen
//Project: Hardware Accelerator for 2D Convolution
//Design: Unpipelined Design for the MAC Unit

module mac #(
        parameter INW = 16,
        parameter OUTW = 64
    )(
        input signed [INW-1:0] input0, input1, init_value,
        output logic signed [OUTW-1:0] out,
        input clk, reset, init_acc, input_valid 
    );
    
    logic signed [2*INW-1:0] prod;
    logic signed [OUTW-1:0] sum;

    always_comb begin : multiplier
        // Multiply input0 and input1 and store result in signal
        prod = input0 * input1;
    end

    always_comb begin : adder
        // Add the result of the multiplier (prod) to the flip-flop output
        sum = prod + out;
    end

    always_ff @(posedge clk) begin : accumulator_register
        // init_acc high: load init_value into reg_out
        // en (input_valid) high: load sum into reg_out
        // reset high: clear reg_out to 0
       
        if (reset == 1) 
            out <= 0;
        else if (init_acc == 1)
            // Accumulator register outputs init_value
            out <= init_value;
        else if (input_valid == 1)
            // Accumulator register outputs sum (D)
            out <= sum;
    end 
endmodule
