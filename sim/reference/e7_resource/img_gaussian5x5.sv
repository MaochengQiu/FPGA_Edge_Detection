`timescale 1ns/1ps
`default_nettype none
// Exact integer binomial kernel [1 4 6 4 1]' * [1 4 6 4 1] / 256.
// Only one final rounding (+128); no intermediate quantization. II=1, 2 stages.
module img_gaussian5x5(input wire clk,rst_n,input wire [199:0] pixels,
    output reg [7:0] pixel);
    reg [11:0] row_sum[0:4];
    genvar r;
    generate for(r=0;r<5;r=r+1)begin:rows
        wire [11:0] a={4'd0,pixels[(r*5)*8+:8]};
        wire [11:0] b={4'd0,pixels[(r*5+1)*8+:8]};
        wire [11:0] c={4'd0,pixels[(r*5+2)*8+:8]};
        wire [11:0] d={4'd0,pixels[(r*5+3)*8+:8]};
        wire [11:0] e={4'd0,pixels[(r*5+4)*8+:8]};
        always @(posedge clk)if(!rst_n)row_sum[r]<=0;
            else row_sum[r]<=(a+e)+((b+d)<<2)+((c<<2)+(c<<1));
    end endgenerate
    wire [15:0] a={4'd0,row_sum[0]},b={4'd0,row_sum[1]},c={4'd0,row_sum[2]},
        d={4'd0,row_sum[3]},e={4'd0,row_sum[4]};
    // Maximum 255*256+128=65408, safely within 16 bits.
    wire [15:0] sum=(a+e)+((b+d)<<2)+((c<<2)+(c<<1))+16'd128;
    always @(posedge clk)if(!rst_n)pixel<=0;else pixel<=sum[15:8];
endmodule
`default_nettype wire
