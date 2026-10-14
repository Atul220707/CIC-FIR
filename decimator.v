
`timescale 1ns/1ns

module decimator #(
    parameter  N         = 5,      // CIC order or number of stages
    parameter  R         = 2048,   // Decimation factor
    parameter  M         = 1,      // Comb differential delay
    parameter  IN_WIDTH  = 2,
    parameter  OUT_WIDTH = 20,  //port width
    parameter OUT_BITS   =20, //REAL RESOLUTION
    parameter WIDTH =IN_WIDTH + N * $clog2(R * M), //Hogenauer's Bound
    parameter SHIFT =WIDTH-OUT_BITS-1 //DROPPING LEAST SIGNIFICANT WIDTHS BUT LEAVING 1 GUARD BITS  
)(
    input  wire clk,
    input  wire rst,enable,
    input  wire signed [IN_WIDTH-1:0]   d_in,

    output reg signed [OUT_WIDTH-1:0]   d_out,
    output reg  ready_out
);
  wire signed [WIDTH-1:0] data = d_in;
    // Integrator registers
    reg signed [WIDTH-1:0] integrator [0:N-1];

integer i;
    always@(posedge clk) begin
        if (rst) begin
            for (i=0;i<N;i=i+1) integrator [i] <=0;
         end
         else if (enable) begin 
          integrator[0]<=integrator[0]+data;
          for (i=1;i<N;i=i+1)
                integrator[i] <= integrator[i] + integrator[i-1];
                end
      end       
reg [$clog2(R)-1:0] count;
wire tick =(count==R-1) && enable;
//decimation counter
always @(posedge clk) begin
   if (rst) count<=0;
   else if(tick) count <=0;
   else if (enable) count <=count+1'b1;
   end
 //combs  
   
    //  combs 
    wire signed [WIDTH-1:0] comb [0:N];
    reg signed [WIDTH-1:0] prev [0:N-1][0:M-1];
    assign comb[0] = integrator[N-1];
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : COMB
            assign comb[g+1] = comb[g] - prev[g][M-1];
        end
    endgenerate

    integer k, j;
    always @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < N; k = k + 1)
                for (j = 0; j < M; j = j + 1)
                    prev[k][j] <= 0;
        end
        else if (tick) begin
            for (k = 0; k < N; k = k + 1) begin
                for (j = M-1; j > 0; j = j - 1)
                    prev[k][j] <= prev[k][j-1];

                prev[k][0] <= comb[k];
            end
        end
    end

  //round+saturati ng to outbits 
   localparam SW = WIDTH -SHIFT;
    wire signed [WIDTH-1:0] half   = {{(WIDTH-1){1'b0}},1'b1} << (SHIFT-1);
    wire signed [WIDTH-1:0] rnd    = comb[N] + half;
    wire signed [SW-1:0]    scaled = rnd[WIDTH-1:SHIFT];
    wire [SW-OUT_BITS:0] top = scaled[SW-1:OUT_BITS-1];
    wire ovf = ~((&top) | (~|top));   // top bits not all-same -> overflow

    wire signed [OUT_BITS-1:0] sat =
        ovf ? (scaled[SW-1] ? {1'b1,{(OUT_BITS-1){1'b0}}}     // most negative
                            : {1'b0,{(OUT_BITS-1){1'b1}}})    // most positive
            : scaled[OUT_BITS-1:0];
            
    always @(posedge clk) begin
        if (rst) begin
            d_out     <= 0;
            ready_out <= 1'b0;
        end else begin
            ready_out <= tick;
            if (tick) d_out <= sat;   // signed -> sign-extends if OUT_WIDTH > OUT_BITS
        end
    end
endmodule

