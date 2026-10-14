`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.10.2026 02:08:52
// Design Name: 
// Module Name: FIR
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



module FIR #(
    parameter IN_WIDTH  = 24, //width of input sample
    parameter OUT_WIDTH = 20,
    parameter OUT_SHIFT = 4      // Additional right shift after removing Q14 coefficient scaling.
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         in_valid,
    input  wire signed [IN_WIDTH-1:0]   d_in,
    output reg  signed [OUT_WIDTH-1:0]  d_out,
    output reg                          out_valid  // will be high for one clock cycle when d_out is updated.
);
    localparam N_TAPS = 25;   //  number of taps 
    localparam HALF  = 12;   // center tap index
    localparam F     = 14;   // coefficient fractional bits
    localparam CW    = 18;  //coefficient width  
    localparam ACCW  = IN_WIDTH + CW + 6; //Accumulator width

    reg signed [IN_WIDTH-1:0] x [0:N_TAPS-1]; //added shift registers for most reent input
    reg signed [ACCW-1:0]     acc;           
    reg [4:0]                 k;//used for folded fir calculation
    reg                       busy;
    integer j;

    // folded coefficient ROM (h[k] = h[24-k]), order 24, Q14
    reg signed [CW-1:0] coef;
    always @(*) begin
        case (k)
             0: coef =  18'sd487;
             1: coef = -18'sd585;
             2: coef =  18'sd711;
             3: coef = -18'sd880;
             4: coef =  18'sd1108;
             5: coef = -18'sd1433;
             6: coef =  18'sd1908;
             7: coef = -18'sd2646;
             8: coef =  18'sd3859;
             9: coef = -18'sd6030;
            10: coef =  18'sd10328;
            11: coef = -18'sd19963;
            12: coef =  18'sd43088;
            default: coef = 18'sd0;
        endcase
    end
 wire signed [IN_WIDTH:0] xa  = x[k];
 wire signed [IN_WIDTH:0] xb  = (k == HALF) ? 0 : x[N_TAPS-1-k];
   wire signed [IN_WIDTH:0] pre = xa + xb;  // all inputs
 wire signed [IN_WIDTH+CW:0] prod = pre * coef; // multiplying with coefficients

//rounding and saturation of result as in cic filter
    localparam SH = F + OUT_SHIFT;
    wire signed [ACCW-1:0] rounded = (acc + (1 <<< (SH-1))) >>> SH;
    localparam signed [ACCW-1:0] MAXV =  (1 <<< (OUT_WIDTH-1)) - 1;//largest value
    localparam signed [ACCW-1:0] MINV = -(1 <<< (OUT_WIDTH-1));//smallest value


//Clearing and coming to idle state
    always @(posedge clk) begin
        if (rst) begin
            for (j = 0; j < N_TAPS; j = j + 1) x[j] <= 0;
            acc <= 0; k <= 0; busy <= 0;
            d_out <= 0; out_valid <= 0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid && !busy) begin
                x[0] <= d_in;
                for (j = 1; j < N_TAPS; j = j + 1) x[j] <= x[j-1];//shifting older sample to higher indices
                acc  <= 0;
                k    <= 0;
                busy <= 1'b1;
            end else if (busy) begin
                acc <= acc + prod;
                if (k == HALF) begin
                    busy <= 1'b0;
                end
                k <= k + 1;
            end else if (k == HALF + 1) begin
                // acc now holds the full sum
                if      (rounded > MAXV) d_out <= MAXV[OUT_WIDTH-1:0]; 
                else if (rounded < MINV) d_out <= MINV[OUT_WIDTH-1:0];  
                else                     d_out <= rounded[OUT_WIDTH-1:0];
                out_valid <= 1'b1;
                k <= 0;
            end
        end
    end
endmodule