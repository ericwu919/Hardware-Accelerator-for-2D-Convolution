// ESE 507 Stony Brook University
// Peter Milder
// You may not redistribute this code.
// Testbench for input_mems module

// To use this testbench:
// Compile it and your accompanying design with:
//   vlog -64 +acc input_mems_tb.sv [add your other .sv files to simulate here]
//   vsim -64 -c input_mems_tb -sv_seed random 
//      [options]:
//       - If you want to run in GUI mode, remove -c

// Note that this testbench relies on params.sv, which can be generated 
// using the ./genParams3 script. See instructions in the project description.



// A class to hold one instance of test data and its expected output. When we call 
// .randomize() on an object of this class, it will randomly generate values for the 
// inputs, weights, bias, the values of R, C, and K, and the value of new_W.
// This class also has two functions force_new_W() and allow_old_W().
// These functions will generate random input values. The difference between 
// these is that force_new_W() will always set new_W=1 while allow_old_W() will 
// randomly pick whether to use the weights or create a new one.
class testdata #(parameter INW=8, parameter R=8, parameter C=7, parameter MAXK=5);
    
    // The bias B
    rand int bias;

    // The value of K
    rand logic [$clog2(MAXK+1)-1:0] K;

    // This constraint means when we randomize an object of this class, it will
    // choose the value of K to be between 2 and MAXK, with
    // equal probability of each number
    constraint c {K dist {[2:MAXK] := 1};}

    // an R x C input matrix
    rand int matrixX[R*C];   
    
    // a MAXK x MAXK weight matrix
    // we will only use KxK of this, but we declare it large enough to accomodate the maximum possible K
    rand int matrixW[MAXK*MAXK];
   
    // These constraints will ensure that the matrixX values and bias fit within INW bits
    constraint m1 {
        if (INW < 32) {
            foreach(matrixX[i]) {
                matrixX[i] < (1<<(INW-1));
                matrixX[i] >= -1*(1<<(INW-1));
            }
        }
    }

    constraint m2 {
        if (INW < 32) {
            bias < (1<<(INW-1));
            bias >= -1*(1<<(INW-1));
        }
    }

    // This constraint will ensure the weight matrix values fit within INW bits
    // and that only KxK entries are used
    constraint m3 {
        foreach(matrixW[i]) {
            if (i < K*K) {
                if (INW < 32) {
                    matrixW[i] < (1<<(INW-1));
                    matrixW[i] >= -1*(1<<(INW-1));
                }
            }            
            else {
                matrixW[i] == 0;
            } 
        }
    }    

    // new_W==0 means this test will use the previous weights and bias; new_W==1 means this
    // test will load new weights and bias
    rand logic new_W;    

    // This will randomize K and all inputs, forcing new_W to 1. We use this at the beginning
    // of the testbench (since there is no old W to re-use!)
    function void force_new_W();
        // randomize everything
        assert(this.randomize());   

        // force new_W to 1
        this.new_W = 1;       
    endfunction

    // This will randomly choose new_W. If it is 1, it will generate a new
    // weight matrix and bias. If it is 0, it will copy the old weights and bias from olddata,
    // while generating a new matrixX.    
    function void allow_old_W(testdata #(INW, R, C, MAXK) olddata);
        // randomize 
        assert(this.randomize());

        // if the random new_W is 0, then we will copy the previous matrixW, bias
        // and K from old_data
        if (this.new_W == 0) begin
            this.matrixW = olddata.matrixW;
            this.K = olddata.K;
            this.bias = olddata.bias;
        end

    endfunction

endclass

`include "params.sv"

module input_mems_tb();

    parameter INW   = `INWVAL;  // INW is the number of bits of each input (X,W,B)
    parameter R     = `RVAL;    // R is the number of rows in the X matrix
    parameter C     = `CVAL;    // C is the number of cols in the X matrix
    parameter MAXK  = `MAXKVAL; // MAXK is the maximum number of rows/cols in K
    parameter TESTS = 10000;    // the number of sets of inputs to simulate

    // The probability that the testbench asserts AXIS_TVALID=1 
    // on any given cycle. You can adjust this value to simulate different 
    // scenarios. Valid values for this parameter are 0.001 to 1. 
    // If the value is set to 0, then it will be randomized when you start
    // your simulation.
    parameter real INPUT_TVALID_PROB = `TVPR;

    localparam K_BITS      = $clog2(MAXK+1);    // the number of bits needed for K
    localparam X_ADDR_BITS = $clog2(R*C);       // number of bits to address X
    localparam W_ADDR_BITS = $clog2(MAXK*MAXK); // number of bits to address largest possible W

    logic clk, reset;
    initial clk=0;
    always #5 clk = ~clk;
    
    // Signals for the DUT's AXI-Stream input interface
    logic signed [INW-1:0] INPUT_TDATA;
    logic INPUT_TVALID;

    // AXIS_TUSER[K_BITS:1] is the value of K during the first W entry
    // AXIS_TUSER[0] is the new_W signal during the first entry
    logic [K_BITS:0] INPUT_TUSER; 
    logic INPUT_TREADY;   

    // control/status signals to the rest of the system
    logic inputs_loaded;        // tells the control module to start computing
    logic compute_finished;     // comes from outside of this module to say we're done with these inputs
    logic [K_BITS-1:0]     K;   // the value of K 
    logic signed [INW-1:0] B;   // the bias value
    
    // memory interfaces to read data from the memories
    logic [X_ADDR_BITS-1:0] X_read_addr;
    logic signed [INW-1:0]  X_data;
    logic [W_ADDR_BITS-1:0] W_read_addr;
    logic signed [INW-1:0]  W_data;

    // instantiate the DUT
    input_mems #(INW, R, C, MAXK) dut(clk, reset, INPUT_TDATA, INPUT_TVALID, INPUT_TUSER, INPUT_TREADY, inputs_loaded, compute_finished, K, B, X_read_addr, X_data, W_read_addr, W_data);

    // This is an array of "testdata" objects. (See definition of the testdata class above.)
    // It will will hold all of our test data. Each "testdata" object holds data for one MMM input.
    testdata #(INW, R, C, MAXK) td[TESTS];

    // generate random bits to use when randomizing INPUT_TVALID 
    logic rb0;
    logic [9:0] randomNum;
    logic [9:0] tvalid_prob;

    initial begin
        // if needed, randomize tvalid_prob
        if (INPUT_TVALID_PROB >= 0.001)
            tvalid_prob = (1024*INPUT_TVALID_PROB-1);
        else
            tvalid_prob = ($urandom % 1024);

        $display("--------------------------------------------------------");
        $display("Starting input_mems simulation: %d tests", TESTS);
        $display("(R,C,MAXK): %d, %d, %d", R, C, MAXK);
        $display("Input %d bits", INW);

        $display("INPUT_TVALID_PROB = %1.3f", real'(tvalid_prob+1)/1024);
        $display("--------------------------------------------------------");

        // check parameters
        if (MAXK >= R) begin
            $error("PARAMETER ERROR: MAXK must be < R");
            $stop;
        end
        if (MAXK >= C) begin
            $error("PARAMETER ERROR: MAXK must be < C");
            $stop;
        end
        if ((R < 3) || (C < 3)) begin
            $error("PARAMETER ERROR: R and C must both be >= 3");
            $stop;
        end
        if (MAXK < 2) begin
            $error("PARAMETER ERROR: MAXK must be >= 2");
            $stop;
        end
        if ((INW >= 32) || (INW < 2)) begin
            $error("PARAMETER ERROR: INW must be 2 <= INW < 32");
            $stop;
        end
    end

    // Every clock cycle, randomly generate rb0 for the INPUT_TVALID signal
    always begin
        @(posedge clk);
        #1;
        randomNum = $urandom;
        rb0 = (randomNum <= tvalid_prob);
    end

    // Logic to keep track of where we are in the test data.
    // which_test keeps track of which of the TESTS test cases we are operating on.
    // which_element keeps track of which input value within this test case we
    // are sending.
    logic [31:0] which_test, which_element; 
    initial which_test=0; 
    initial which_element=0;
    always @(posedge clk) begin
        if (INPUT_TVALID && INPUT_TREADY) begin        
            if (which_element == R*C + td[which_test].K*td[which_test].K + 1 - 1) begin // if we just finished loading this test...
                which_test <= #1 which_test+1;   // increment to next test

                // if we are not at the last test:
                if (which_test < TESTS-1) begin
                    // if the next test has a new_W, set the counter back to 0
                    if (td[which_test+1].new_W == 1) begin
                        which_element <= #1 0;
                    end
                    else begin // if it doesn't have a new_W, set the counter to the matrixX location
                        which_element <= #1 td[which_test+1].K * td[which_test+1].K + 1;
                    end
                end

            end
            else begin   // or if we are in the middle of a test, just increment
                which_element <= #1 which_element+1;
            end        
        end
    end

    // Logic to set INPUT_TVALID based on random value rb0.
    always @* begin
        // If we haven't finished all of our test inputs and the random bit rb0 is 1,
        if ((which_test < TESTS) && (rb0==1'b1))
            INPUT_TVALID=1;
        else
            INPUT_TVALID=0;
    end

    // Logic to set the value of INPUT_TDATA based on the random input value and the 
    // which_element and which_test variables
    always @(which_element or which_test or INPUT_TVALID) begin
        INPUT_TDATA = 'x;
         if (INPUT_TVALID == 1) begin
            if (which_element < td[which_test].K * td[which_test].K) begin  // we are loading the weights
                INPUT_TDATA = td[which_test].matrixW[which_element];
            end
            else if (which_element == td[which_test].K * td[which_test].K) // we are loading the bias
                INPUT_TDATA = td[which_test].bias;
            else begin // we are loading matrixX
                INPUT_TDATA = td[which_test].matrixX[which_element-(td[which_test].K * td[which_test].K + 1)];
            end            
        end
    end    

    // Logic to set the value of INPUT_TUSER based on the random input value and the 
    // which_element and which_test variables
    always @(INPUT_TVALID or which_test or which_element) begin
        INPUT_TUSER = 'x;
         if (INPUT_TVALID == 1) begin
            if ((td[which_test].new_W == 1) && (which_element == 0))
                INPUT_TUSER = {td[which_test].K, 1'b1};
            else 
                INPUT_TUSER = 0;
        end
    end    


    // generate our test input data and expected output data
    initial begin        
        td[0]=new();
        td[0].force_new_W(); // the first test needs a new_W

        for (int i=1; i<TESTS; i++) begin
            td[i]=new();
            td[i].allow_old_W(td[i-1]);     
        end
    end
    
    logic [31:0] which_test_out; 
    integer errors = 0;
    initial which_test_out = 0;

    integer cycle_count=0;

    // when inputs_loaded is 1, check the K and B outputs of the DUT
    // are correct
    always @(posedge clk) begin
        if ((inputs_loaded == 1) && (K !== td[which_test_out].K)) begin
            $display($time,, "ERROR: Test %d, K = %d; expected value = %d", which_test_out, K, td[which_test_out].K);
            errors = errors+1;
        end
        if ((inputs_loaded == 1) && (B !== td[which_test_out].bias)) begin
            $display($time,, "ERROR: Test %d, B = %d; expected value = %d", which_test_out, B, td[which_test_out].bias);
            errors = errors+1;
        end

    end 

    // Logic to check the outputs and keep track of which output test you are checking
    initial begin
        compute_finished = 0;

        while (which_test_out < TESTS) begin
            wait (inputs_loaded == 1); #1; // wait until inputs are loaded into memory

            // Read the DUT's matrixX and matrixW memories and check correctness
            W_read_addr = 0;
            for (int i=1; i <= td[which_test_out].K*td[which_test_out].K; i++) begin
                @(posedge clk);
                #1;
                if (W_data !== td[which_test_out].matrixW[i-1]) begin
                    $display($time,,"ERROR: Test %d, W_data[%d] = %d; expected value = %d", which_test_out, i-1, W_data, td[which_test_out].matrixW[i-1]);
                    errors = errors+1;
                end

                W_read_addr = i;                
            end
            X_read_addr = 0;
            for (int i=1; i <= R*C; i++) begin
                @(posedge clk);
                #1;
                if (X_data !== td[which_test_out].matrixX[i-1]) begin
                    $display($time,,"ERROR: Test %d, X_data[%d] = %d; expected value = %d", which_test_out, i-1, X_data, td[which_test_out].matrixX[i-1]);
                    errors = errors+1;
                end         

                X_read_addr = i;       
            end

            if (errors >= 100) begin
                $display($time,, "100 errors reached. Stopping simulation early.");
                $finish;
            end

            // Toggle "compute_finished" so the DUT can start on its next task
            #1;
            compute_finished = 1;

            @(posedge clk);
            #1;
            compute_finished = 0;
            which_test_out = which_test_out+1;
        end
    end

    // Logic to assert reset at the beginning, then wait until all tests are done,
    // print the results, and then quit the simulation.
    initial begin
        reset = 1;        
        @(posedge clk); #1; reset = 0; 

        wait(which_test_out == TESTS);
        $display("Simulated %d tests. Detected %d errors.", TESTS, errors);
        #1;
        $finish;
    end

    // logic to stop simulation if no progress is being made
    logic [31:0] which_test_out_last, which_element_out_last;
    initial begin
        forever begin
            which_test_out_last = which_test_out;

            repeat (1000000) @(posedge clk);
            
            if (which_test_out == which_test_out_last) begin
                $error();
                $display("");
                $display("");
                $display("");
                $display("------------------------ Timeout Error ------------------------");
                $display("ERROR: The testbench has not made progress in the last 1,000,000 cycles. Terminating.");
                $display("The simulation was not successful");
                $display("");
                $display("The testbench made it up to the following input and output before terminating: ");
                $display("    input: td[%d][%d]; output: td[%d][]", which_test, which_element, which_test_out);
                $display("---------------------------------------------------------------");
                $display("");
                $display("");
                $display("");
                $finish;
            end
        end
    end
  

endmodule


