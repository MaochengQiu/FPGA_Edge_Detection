`timescale 1ns/1ps
`default_nettype none
// Canny extension helper, combinational four-bin direction (not edge tangent).
// 0=0deg, 1=45deg, 2=90deg, 3=135deg. No atan/divider.
module img_gradient_direction(input wire signed [10:0] gx,gy,
                             output reg [1:0] direction);
    wire [10:0] ax=gx[10]?$unsigned(-gx):$unsigned(gx);
    wire [10:0] ay=gy[10]?$unsigned(-gy):$unsigned(gy);
    wire [22:0] scaled_x={12'd0,ax}*23'd424;
    wire [22:0] scaled_y={12'd0,ay}*23'd424;
    always @* begin
        if (({12'd0,ay}<<10)<=scaled_x) direction=0;
        else if (({12'd0,ax}<<10)<=scaled_y) direction=2;
        else direction=(gx[10]^gy[10])?2'd3:2'd1;
    end
endmodule

`default_nettype wire
