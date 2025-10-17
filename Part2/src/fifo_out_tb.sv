// ESE 507 Stony Brook University
// Peter Milder
// You may not redistribute this code.
// Testbench for fifo_out module


// To use this testbench:
// Compile it and your accompanying design with:
//  vlog -64 +acc fifo_out_tb.sv fifo_out.sv [and include any other design files]
//  vsim -64 -c fifo_out_tb -sv_seed random
// (add/adjust options as needed)
//       - If you want to run in GUI mode, remove -c

// Note that this testbench relies on params.sv, which can be generated 
// using the ./genParams2 script. See instructions in the project description.

`include "params.sv"

module fifo_out_tb();
    parameter OUTW=`OUTWVAL;    // the number of bits in each output 
    parameter DEPTH=`DEPTHVAL;  // the depth of the FIFO
    parameter TESTS=10000;      // the number of values to simulate 

    // The probability that the testbench attempts to write a value to the FIFO
    // and assert the output port's TREADY signal on any given cycle. 
    // You can adjust these values to simulate different scenarios.
    // Valid values for these parameters are 0.001 to 1. 
    // If a value is set to 0, then it will be randomized when you start
    // your simulation.
    parameter real TVALID_PROB = `TVPR;
    parameter real TREADY_PROB = `TRPR;

    logic clk, reset;

    initial clk=0;
    always #5 clk = ~clk;

    // Signals for AXI Stream input and output of FIFO
    logic [OUTW-1:0] IN_AXIS_TDATA, OUT_AXIS_TDATA;
    logic            IN_AXIS_TVALID, IN_AXIS_TREADY, OUT_AXIS_TVALID, OUT_AXIS_TREADY;

    // Instance of the DUT we are simulating
    fifo_out #(OUTW, DEPTH) dut(clk, reset, IN_AXIS_TDATA, IN_AXIS_TVALID, IN_AXIS_TREADY, OUT_AXIS_TDATA, OUT_AXIS_TVALID, OUT_AXIS_TREADY);

    logic [9:0] tvalid_prob, tready_prob;

    initial begin
        // If needed randomize the probability parameters
        if (TVALID_PROB >= 0.001)
            tvalid_prob = (1024*TVALID_PROB-1);
        else
            tvalid_prob = ($urandom % 1024);

        if (TREADY_PROB >= 0.001)
            tready_prob = (1024*TREADY_PROB-1);
        else
            tready_prob = ($urandom % 1024);

        // parameter checks
        if (OUTW > 64) begin
            $error("PARAMETER ERROR: OUTW must be <= 64");
            $stop;
        end
        if (DEPTH < 2) begin
            $error("PARAMETER ERROR: DEPTH must be >= 2");
            $stop;
        end

        $display("--------------------------------------------------------");
        $display("Starting simulation of output FIFO: %d tests", TESTS);
        $display("Number of bits: %d", OUTW);
        $display("FIFO Depth: %d", DEPTH);
        $display("IN_TVALID_PROB = %1.3f", real'(tvalid_prob+1)/1024);
        $display("OUT_TREADY_PROB = %1.3f", real'(tready_prob+1)/1024);            
        $display("--------------------------------------------------------");
    end


    // randomize IN_AXIS_TVALID and OUT_AXIS_TREADY
    logic rb0, rb1;
    logic [9:0] randomNum;
    always begin
        @(posedge clk);
        #1;
        randomNum = $urandom;
        rb0 = (randomNum <= tvalid_prob);
        randomNum = $urandom;
        rb1 = (randomNum <= tready_prob); 
    end

    // count the number of inputs loaded
    logic [31:0] in_count;
    initial in_count=0;
    always @(posedge clk) begin
        if (IN_AXIS_TVALID && IN_AXIS_TREADY)
            in_count <= #1 in_count+1;
    end    

    // assign IN_AXIS_TDATA and write based on random rb0
    always @* begin
        if ((in_count < TESTS) && (rb0 == 1)) begin
            IN_AXIS_TVALID = 1;
            IN_AXIS_TDATA = in_count;
        end
        else begin
            IN_AXIS_TVALID = 0;
            IN_AXIS_TDATA = 'bx;
        end
    end
        
    // assign the ready based on random rb1
    logic [63:0] out_count;
    initial out_count=0;
    always @* begin
        if ((out_count >= 0) && (out_count < TESTS) && (rb1==1'b1))
            OUT_AXIS_TREADY = 1;
        else
            OUT_AXIS_TREADY = 0;
    end        

    integer errors=0;

    // count and check the number of outputs received
    always @(posedge clk) begin
        if (OUT_AXIS_TREADY && OUT_AXIS_TVALID) begin
                if (out_count[OUTW-1:0] === OUT_AXIS_TDATA)
                    ; //$display($time,, "SUCCESS: out[%d] = %d", out_count, OUT_AXIS_TDATA);
                else begin
                    $display($time,, "ERROR:   out[%d] = %d; expected %d", out_count, OUT_AXIS_TDATA, out_count[OUTW-1:0]);
                    errors = errors+1;

                    if (errors >= 100) begin
                        $display($time,, "100 errors reached. Stopping simulation early.");
                        $finish;
                    end
                end
            out_count <= out_count+1;
        end
    end

    initial begin
        reset = 1;
        @(posedge clk);
        #1;
        reset = 0;

        wait(out_count==TESTS);
        #10;
        $display("Tested %d inputs. %d errors", TESTS, errors);
        $stop;
    end

    // logic to stop simulation if no progress is being made
    logic [31:0] out_count_last;
    initial begin
        forever begin
            out_count_last = out_count;

            repeat (1000000) @(posedge clk);
            
            if (out_count == out_count_last) begin
                $error();
                $display("");
                $display("");
                $display("");
                $display("------------------------ Timeout Error ------------------------");
                $display("ERROR: The testbench has not made progress in the last 1,000,000 cycles. Terminating.");
                $display("The simulation was not successful");
                $display("");
                $display("The testbench made it up to the following output before terminating: ");
                $display("    output[%d]", out_count);
                $display("---------------------------------------------------------------");
                $display("");
                $display("");
                $display("");
                $finish;
            end
        end
    end

endmodule
