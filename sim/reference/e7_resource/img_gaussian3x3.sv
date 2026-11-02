`timescale 1ns/1ps
`default_nettype none
// Separable binomial 1-2-1 kernel, denominator 16; rounded, one stage.
module img_gaussian3x3(input wire clk,rst_n,input wire [71:0] pixels,
                      output reg [7:0] pixel);
    wire [11:0] sum={4'd0,pixels[7:0]}+({4'd0,pixels[15:8]}<<1)+{4'd0,pixels[23:16]}+
        ({4'd0,pixels[31:24]}<<1)+({4'd0,pixels[39:32]}<<2)+({4'd0,pixels[47:40]}<<1)+
        {4'd0,pixels[55:48]}+({4'd0,pixels[63:56]}<<1)+{4'd0,pixels[71:64]}+12'd8;
    always @(posedge clk) if (!rst_n) pixel<=0;else pixel<=sum[11:4];
endmodule

`default_nettype wire
