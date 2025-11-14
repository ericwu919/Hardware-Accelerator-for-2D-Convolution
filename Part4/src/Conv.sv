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
    logic [INW-1:0] X_data_sent, W_data_sent, B_data_sent;   //data sent from Input Memory Module to MAC Unit
    logic [OUTW-1:0] computedData;  //data from the MAC to the Output FIFO

    /*-----------------------------------------Instantiations of Input Memories, Pipelined MAC, and Output FIFO modules-----------------------------------------*/
    input_mems inputMems_inst(.clk(clk), .reset(reset), .AXIS_TDATA(INPUT_TDATA), .AXIS_TUSER(INPUT_TUSER), .AXIS_TVALID(INPUT_TVALID), .AXIS_TREADY(INPUT_TREADY), 
    .X_read_addr(), .X_data(X_data_sent), .W_read_addr(), .W_data(W_data_sent), .inputs_loaded(), .compute_finished(), .K(), .B(B_data_sent));

    mac_pipe macPipe_inst(.clk(clk), .reset(reset), .input0(X_data_sent), .input1(W_data_sent), .input_valid(), .init_value(B_data_sent), .init_acc(), .out(computedData));

    fifo_out fifoOut_inst(.clk(clk), .reset(reset), .IN_AXIS_TDATA(computedData), .IN_AXIS_TVALID(), .IN_AXIS_TREADY(), 
    .OUT_AXIS_TDATA(OUTPUT_TDATA), .OUT_AXIS_TVALID(OUTPUT_TVALID), .OUT_AXIS_TREADY(OUTPUT_TREADY));

    //Main execution of 2D Convolution
    always_ff @(posedge clk) begin : main
        
    end

endmodule    
