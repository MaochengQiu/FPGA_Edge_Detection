`timescale 1ns/1ps
`default_nettype none
// Rounded BT.601 approximation: (77R+150G+29B+128)>>8. One stage.
module img_rgb2gray(input wire clk,rst_n,input wire [23:0] rgb,
                   output reg [7:0] gray);
    wire [15:0] weighted=({8'd0,rgb[23:16]}*16'd77)+
                         ({8'd0,rgb[15:8]}*16'd150)+
                         ({8'd0,rgb[7:0]}*16'd29)+16'd128;
    always @(posedge clk) if (!rst_n) gray<=0;else gray<=weighted[15:8];
endmodule

`default_nettype wire
