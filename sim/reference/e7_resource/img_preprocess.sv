`timescale 1ns/1ps
`default_nettype none
// Legacy: 0 bypass, 1 median3, 2 Gaussian3, 3 sharpen.
// E7 quality: 0 bypass, 1 median3, 2 Gaussian5, 3 Gaussian3 (no sharpen).
// Quality modes share a centered 5x5 window; invalid 2-pixel filter rim is zero.
// All modes keep identical latency, maintaining original video timing.
// ctl={sof,vs,hs,de}. cfg is a frame snapshot, stable until next input SOF.
module img_preprocess #(parameter integer WIDTH=1920,HEIGHT=1080,HTOTAL=2200,parameter QUALITY_FILTER_ENABLE=1'b0)(
    input wire clk,rst_n,input wire [7:0] pixel,input wire [3:0] ctl,
    input wire [1:0] cfg_mode,
    output wire [7:0] out_pixel,output wire [3:0] out_ctl
);
    localparam integer WIN_DELAY=QUALITY_FILTER_ENABLE?(2*HTOTAL+4):(HTOTAL+3);
    wire [71:0] win;wire win_valid;
    wire [3:0] win_ctl;
    wire [7:0] center_raw,median,gauss,gauss_d,raw_d;
    wire [7:0] sharpen_center,sharpen_d;
    // Arithmetic is signed and saturated: 3*center - 2*Gaussian.
    // All intermediates fit in signed 12 bits (range -510 ... +765).
    wire signed [11:0] sharpen_num =
        $signed({4'b0000,sharpen_center}) +
        ($signed({4'b0000,sharpen_center}) <<< 1) -
        ($signed({4'b0000,gauss}) <<< 1);
    wire [7:0] sharpen_pixel = (sharpen_num < 0) ? 8'd0 :
        (sharpen_num > 12'sd255) ? 8'd255 : sharpen_num[7:0];
    wire valid_d;
    reg [1:0] active_mode;
    wire [199:0] win5;
    wire [7:0] gauss5,gauss5_d;
    generate if(QUALITY_FILTER_ENABLE)begin:g_quality_window
        img_window5x5 #(.BITS(8),.WIDTH(WIDTH),.HEIGHT(HEIGHT)) window_gen5(
            .clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),.pixel(pixel),
            .window(win5),.window_valid(win_valid));
        // The center 3x3 of the SAME window; all filter outputs share its center.
        for(genvar r=0;r<3;r=r+1)begin:rows
            for(genvar c=0;c<3;c=c+1)begin:cols
                assign win[(3*r+c)*8+:8]=win5[((r+1)*5+c+1)*8+:8];
            end
        end
        img_gaussian5x5 gaussian5(.clk(clk),.rst_n(rst_n),.pixels(win5),.pixel(gauss5));
        img_delay #(.BITS(8),.CYCLES(7)) gauss5_align(
            .clk(clk),.rst_n(rst_n),.din(gauss5),.dout(gauss5_d));
    end else begin:g_legacy_window
    img_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) window_gen(
        .clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),.pixel(pixel),
        .window(win),.window_valid(win_valid));
        assign win5=0;assign gauss5=0;assign gauss5_d=0;
    end endgenerate
    img_delay #(.BITS(4),.CYCLES(WIN_DELAY)) ctl_center(
        .clk(clk),.rst_n(rst_n),.din(ctl),.dout(win_ctl));
    img_delay #(.BITS(8),.CYCLES(WIN_DELAY)) bypass_center(
        .clk(clk),.rst_n(rst_n),.din(pixel),.dout(center_raw));
    img_median9 median_net(.clk(clk),.rst_n(rst_n),.pixels(win),.median(median));
    img_gaussian3x3 gaussian(.clk(clk),.rst_n(rst_n),.pixels(win),.pixel(gauss));
    // Center and Gaussian are both registered once. The 8-cycle delay
    // makes sharpen identical in latency to Gaussian (9 stages total),
    // with no extra video sync delay or line buffer.
    img_delay #(.BITS(8),.CYCLES(1)) sharpen_center_reg(
        .clk(clk),.rst_n(rst_n),.din(win[39:32]),.dout(sharpen_center));
    img_delay #(.BITS(8),.CYCLES(8)) sharpen_align(
        .clk(clk),.rst_n(rst_n),.din(sharpen_pixel),.dout(sharpen_d));
    img_delay #(.BITS(8),.CYCLES(8)) gauss_align(
        .clk(clk),.rst_n(rst_n),.din(gauss),.dout(gauss_d));
    img_delay #(.BITS(8),.CYCLES(9)) bypass_align(
        .clk(clk),.rst_n(rst_n),.din(center_raw),.dout(raw_d));
    img_delay #(.BITS(1),.CYCLES(9)) valid_align(
        .clk(clk),.rst_n(rst_n),.din(win_valid),.dout(valid_d));
    img_delay #(.BITS(4),.CYCLES(9)) ctl_align(
        .clk(clk),.rst_n(rst_n),.din(win_ctl),.dout(out_ctl));
    // Selection occurs after the network: local SOF updates its own frame state.
    always @(posedge clk) if (!rst_n) active_mode<=0;
        else if (out_ctl[3]) active_mode<=cfg_mode;
    wire [1:0] mode=out_ctl[3]?cfg_mode:active_mode;
    assign out_pixel=(mode==0)?raw_d:(!valid_d?8'd0:((mode==1)?median:((mode==2)?(QUALITY_FILTER_ENABLE?gauss5_d:gauss_d):(QUALITY_FILTER_ENABLE?gauss_d:sharpen_d))));
endmodule

`default_nettype wire
