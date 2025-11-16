module Conv #(
    parameter INW = 18, //number of bits for each input data word
    parameter R = 8,    //number of rows in the X matrix
    parameter C = 8,    //number of columns in the X matrix
    parameter MAXK = 5, // maximum value of K (rows and columns of W) that is supported
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
    
    /*-----------------------------------------Internal signals for the top level-----------------------------------------*/
    //signals that hold the read addresses for the X and W matrices
    logic [$clog2(R*C)-1:0] x_addr;
    logic [$clog2(MAXK*MAXK)-1:0] w_addr;
    
    //data sent from Input Memory Module to MAC Unit
    logic [INW-1:0] X_data_sent, W_data_sent, B_data_sent;
    logic [K_BITS-1:0] K_data_sent;

    logic initAccCtrl;  //signal for the init_acc value that goes into the MAC
    logic readyCompute; //signal to indicate data matrices stored in memory are complete and are ready for computation in the MAC unit
    logic [OUTW-1:0] computedData;  //data from the MAC to the Output FIFO

    /*Note: If FIFO is full (IN_AXIS_TREADY == 0), MAC must stall until there is space in the FIFO to store the computed data*/

    logic finished;   //signal to indicate the full convolution is completed (FIFO is empty)
    

    /*-----------------------------------------Instantiations of Input Memories, Pipelined MAC, and Output FIFO modules-----------------------------------------*/
    input_mems inputMems_inst #(INW, R, C, MAXK) (.clk(clk), .reset(reset), .AXIS_TDATA(INPUT_TDATA), .AXIS_TUSER(INPUT_TUSER), .AXIS_TVALID(INPUT_TVALID), .AXIS_TREADY(INPUT_TREADY), 
    .X_read_addr(x_addr), .X_data(X_data_sent), .W_read_addr(w_addr), .W_data(W_data_sent), .inputs_loaded(readyCompute), .compute_finished(finished), .K(K_data_sent), .B(B_data_sent));

    mac_pipe macPipe_inst #(INW, OUTW) (.clk(clk), .reset(reset), .input0(X_data_sent), .input1(W_data_sent), .input_valid(readyCompute), .init_value(B_data_sent), .init_acc(), .out(computedData));

    fifo_out fifoOut_inst #(OUTW, C-1) (.clk(clk), .reset(reset), .IN_AXIS_TDATA(computedData), .IN_AXIS_TVALID(), .IN_AXIS_TREADY(), 
    .OUT_AXIS_TDATA(OUTPUT_TDATA), .OUT_AXIS_TVALID(OUTPUT_TVALID), .OUT_AXIS_TREADY(OUTPUT_TREADY));

    /*-----------------------------------------Top level module control logic-----------------------------------------*/
    //Control logic for reading X and W input data from the input memories and feeding them 
    //(and value of B) into the MAC module by controlling their respective read addresses
    always_comb begin : addr_control
        //X matrix address
        if (x_addr == R*C) begin
            x_addr = 0;
        else
            //matrices are stored in row-major order
            x_addr = x_addr + 1;
        end

        //W matrix address
        if (w_addr == MAXK*MAXK) begin
            w_addr = 0;
        else
            //matrices are stored in row-major order
            w_addr = w_addr + 1;
        end
    end 

    //Control logic for the MAC modules' control inputs (init_acc , init_value, input_valid)
    always_comb begin : mac_control
        readyCompute = (inputs_loaded) ? 1 : 0;
        
    end 

    //Control logic for the FIFO's IN_AXIS_TVALID and IN_AXIS_TREADY input interface ports
    always_comb begin : fifo_control

    end 

    //Control logic for the state of compute_finished input port in the input memory module
    always_comb begin : finished_control
        finished = !OUTPUT_TVALID;
    end    

endmodule    
