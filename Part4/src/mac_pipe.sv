module mac_pipe #(
        parameter INW = 24,
        parameter OUTW = 48
    )(
        input signed [INW-1:0] input0, input1, init_value,
        output logic signed [OUTW-1:0] out,
        input clk, reset, init_acc, input_valid 
    );

    logic signed [2*INW-1:0] prod;  //result of multiplier
    logic signed [OUTW-1:0] sum;    //result of adder
    logic signed [2*INW-1:0] mult_reg_output;   //multiply register output
    logic enable_delayed;

    always_comb begin : multiplier
        // Multiply input0 and input1 and store result in signal
        prod = input0 * input1;
    end

    always_ff @(posedge clk) begin : multiply_register
        // Register that holds the output of multiplier, input_valid can not be used now
        if (reset == 1) begin
            mult_reg_output <= '0;
            enable_delayed <= 1'b0;
        end else begin
            mult_reg_output <= prod;
            enable_delayed <= input_valid;
        end
    end
    
    always_comb begin : adder
        // Add the result of the multiplier (prod) to the flip-flop output
        sum = mult_reg_output + out;
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
        else if (enable_delayed == 1)
            // Accumulator register outputs sum (D)
            out <= sum;
    end 

endmodule