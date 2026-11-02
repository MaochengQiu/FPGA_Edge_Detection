`timescale 1ns/1ps
`default_nettype none
// Standalone RGB888 raster kernel. Every mode has TOTAL_LATENCY=2*HTOTAL+22.
// Positive HS/VS; no backpressure. Config snapshot must last one input frame.
module img_pipeline #(parameter integer WIDTH=1920,HEIGHT=1080,HTOTAL=2200)(
    input wire clk,rst_n,input wire [23:0] in_rgb,input wire in_de,in_hs,in_vs,
    input wire [1:0] cfg_preprocess,input wire [10:0] cfg_threshold,
    input wire [2:0] cfg_display,
    output wire [23:0] out_rgb,output wire out_de,out_hs,out_vs,
    output wire [10:0] debug_magnitude,output wire debug_edge,
    output wire input_sof
);
    localparam integer WIN_DELAY=HTOTAL+3;
    localparam integer PRE_DELAY=WIN_DELAY+9;
    localparam integer TO_EDGE=PRE_DELAY+WIN_DELAY+4+1;
    wire [15:0] ix,iy;wire unused_eol;
    wire [3:0] in_ctl={input_sof,in_vs,in_hs,in_de};
    wire [3:0] gray_ctl,pre_ctl,win_ctl,grad_ctl,edge_ctl,composed_ctl;
    wire [7:0] gray,pre_pixel;
    wire [23:0] rgb_d1;
    wire [31:0] original_aligned;
    wire [71:0] sobel_win;wire win_valid,gradient_valid;
    wire signed [10:0] gx,gy;wire [10:0] mag;
    wire [15:0] ex,ey;wire esof,eeol;
    reg [10:0] active_threshold;
    reg [1:0] active_pre;
    reg edge_q;reg [10:0] mag_q;
    wire [10:0] threshold=grad_ctl[3]?cfg_threshold:active_threshold;
    wire [1:0] pre_mode=grad_ctl[3]?cfg_preprocess:active_pre;
    wire [15:0] radius=(pre_mode==0)?16'd1:16'd2;
    wire interior=(ex>=radius && ex<WIDTH-radius && ey>=radius && ey<HEIGHT-radius);
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) input_coords(
        .clk(clk),.rst_n(rst_n),.de(in_de),.vs(in_vs),.x(ix),.y(iy),
        .sof(input_sof),.eol(unused_eol));
    img_rgb2gray gray_op(.clk(clk),.rst_n(rst_n),.rgb(in_rgb),.gray(gray));
    img_delay #(.BITS(4),.CYCLES(1)) gray_timing(
        .clk(clk),.rst_n(rst_n),.din(in_ctl),.dout(gray_ctl));
    img_delay #(.BITS(24),.CYCLES(1)) original_first(
        .clk(clk),.rst_n(rst_n),.din(in_rgb),.dout(rgb_d1));
    img_preprocess #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL)) preprocess(
        .clk(clk),.rst_n(rst_n),.pixel(gray),.ctl(gray_ctl),.cfg_mode(cfg_preprocess),
        .out_pixel(pre_pixel),.out_ctl(pre_ctl));
    img_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) gradient_window(
        .clk(clk),.rst_n(rst_n),.de(pre_ctl[0]),.vs(pre_ctl[2]),.pixel(pre_pixel),
        .window(sobel_win),.window_valid(win_valid));
    img_delay #(.BITS(4),.CYCLES(WIN_DELAY)) window_timing(
        .clk(clk),.rst_n(rst_n),.din(pre_ctl),.dout(win_ctl));
    img_sobel_gradient gradient(.clk(clk),.rst_n(rst_n),.pixels(sobel_win),
        .gx(gx),.gy(gy),.magnitude(mag));
    img_delay #(.BITS(1),.CYCLES(4)) gradient_valid_d(
        .clk(clk),.rst_n(rst_n),.din(win_valid),.dout(gradient_valid));
    img_delay #(.BITS(4),.CYCLES(4)) gradient_timing(
        .clk(clk),.rst_n(rst_n),.din(win_ctl),.dout(grad_ctl));
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) edge_coords(
        .clk(clk),.rst_n(rst_n),.de(grad_ctl[0]),.vs(grad_ctl[2]),.x(ex),.y(ey),
        .sof(esof),.eol(eeol));
    always @(posedge clk) begin
        if (!rst_n) begin active_threshold<=0;active_pre<=0;edge_q<=0;mag_q<=0;end
        else begin
            if (grad_ctl[3]) begin active_threshold<=cfg_threshold;active_pre<=cfg_preprocess;end
            edge_q<=grad_ctl[0] && gradient_valid && interior && mag>=threshold;
            mag_q<=(grad_ctl[0] && gradient_valid && interior)?mag:11'd0;
        end
    end
    img_delay #(.BITS(4),.CYCLES(1)) edge_timing(
        .clk(clk),.rst_n(rst_n),.din(grad_ctl),.dout(edge_ctl));
    img_delay #(.BITS(32),.CYCLES(TO_EDGE)) original_alignment(
        .clk(clk),.rst_n(rst_n),.din({rgb_d1,gray}),.dout(original_aligned));
    img_composer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) composer(
        .clk(clk),.rst_n(rst_n),.ctl(edge_ctl),.rgb(original_aligned[31:8]),
        .gray(original_aligned[7:0]),.edge_pixel(edge_q),.magnitude(mag_q),
        .cfg_display(cfg_display),.out_rgb(out_rgb),.out_ctl(composed_ctl));
    assign {out_vs,out_hs,out_de}=composed_ctl[2:0];
    assign debug_magnitude=mag_q;assign debug_edge=edge_q;
endmodule

`default_nettype wire
