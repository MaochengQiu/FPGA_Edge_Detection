`timescale 1ns/1ps
`default_nettype none
// HDMI-domain, after Debayer. Independent from the original JTAG raw Bayer gain.
// Gain format UQ2.8, 0x100=1.0. All RGB and timing share exactly ONE cycle.
// Gain changes are sampled at input VS rising edge and held for a complete frame.
module edge_color_balance(
    input wire clk,rst_n,
    input wire [23:0] in_rgb,
    input wire in_de,in_hs,in_vs,
    input wire [9:0] gain_r,gain_g,gain_b,
    output reg [23:0] raw_rgb,bal_rgb,
    output reg [2:0] clipped_rgb, // {R,G,B}, true gain overflow, aligned with RGB
    output reg out_de,out_hs,out_vs
);
    reg prev_vs;
    reg [9:0] rg,gg,bg;
    wire new_frame=in_vs && !prev_vs;
    wire [9:0] r_sel=new_frame?gain_r:rg;
    wire [9:0] g_sel=new_frame?gain_g:gg;
    wire [9:0] b_sel=new_frame?gain_b:bg;
    wire [17:0] mr=in_rgb[23:16]*r_sel;
    wire [17:0] mg=in_rgb[15:8]*g_sel;
    wire [17:0] mb=in_rgb[7:0]*b_sel;
    // C1: add half an LSB before shifting; keep the carry until saturation.
    // Unity is bit-exact, dark fractional values are no longer always rounded
    // down, and a bright product can never wrap to a dark byte.
    wire [18:0] rr={1'b0,mr}+19'd128;
    wire [18:0] gr={1'b0,mg}+19'd128;
    wire [18:0] br={1'b0,mb}+19'd128;
    function [7:0] sat8(input [18:0] rounded);
        begin sat8=(|rounded[18:16])?8'hff:rounded[15:8]; end
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_vs<=0;rg<=10'h100;gg<=10'h100;bg<=10'h100;
            raw_rgb<=0;bal_rgb<=0;clipped_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            prev_vs<=in_vs;
            if(new_frame)begin rg<=gain_r;gg<=gain_g;bg<=gain_b;end
            raw_rgb<=in_rgb;
            bal_rgb<={sat8(rr),sat8(gr),sat8(br)};
            clipped_rgb<=in_de?{(|rr[18:16]),(|gr[18:16]),(|br[18:16])}:3'd0;
            out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;
        end
    end
endmodule
`default_nettype wire
