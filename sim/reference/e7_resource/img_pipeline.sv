`timescale 1ns/1ps
`default_nettype none
// RGB888 kernel: legacy latency 5*HTOTAL+60; E7 quality 6*HTOTAL+61.
// Every display and PRE mode retains identical latency within each configuration.
// One extra line + 5 clocks for NMS, also present in the Sobel A/B bypass.
// Positive HS/VS; no backpressure. Config snapshot must last one input frame.
module img_pipeline #(parameter integer WIDTH=1920,HEIGHT=1080,HTOTAL=2200,
    parameter NMS_ENABLE=1'b0,NMS_STRICT_TIES=1'b0,LINK_ENABLE=1'b0,LINK_MIN_SEEDS=3,
    parameter COMPARE_PAIR_EDGE=1'b1,WEAK_CHAIN_ENABLE=1'b0,QUALITY_FILTER_ENABLE=1'b0)(
    input wire clk,rst_n,input wire [23:0] in_rgb,input wire in_de,in_hs,in_vs,
    input wire [1:0] cfg_preprocess,input wire [10:0] cfg_threshold,
    input wire [2:0] cfg_display,
    output wire [23:0] out_rgb,output wire out_de,out_hs,out_vs,
    output wire [10:0] debug_magnitude,output wire debug_edge,
    output wire input_sof
);
    localparam integer WIN_DELAY=HTOTAL+3;
    localparam integer PRE_DELAY=WIN_DELAY+9+(QUALITY_FILTER_ENABLE?(HTOTAL+1):0);
    localparam integer TO_EDGE=PRE_DELAY+WIN_DELAY+4+1;
    localparam integer NMS_DELAY=HTOTAL+5;
    localparam integer LINK_DELAY=2*HTOTAL+32;
    wire [15:0] ix,iy;wire unused_eol;
    wire [3:0] in_ctl={input_sof,in_vs,in_hs,in_de};
    wire [3:0] gray_ctl,pre_ctl,win_ctl,grad_ctl,edge_ctl,composed_ctl;
    wire [7:0] gray,pre_pixel;
    wire [23:0] rgb_d1;
    wire [23:0] original_aligned;
    wire [71:0] sobel_win;wire win_valid,gradient_valid;
    wire signed [10:0] gx,gy;wire [10:0] mag;
    wire [15:0] ex,ey;wire esof,eeol;
    reg [10:0] active_threshold;
    reg [1:0] active_pre;
    reg edge_q;reg [10:0] mag_q;
    wire [1:0] direction;reg [1:0] direction_q;reg valid_q,low_q;
    wire [10:0] threshold=grad_ctl[3]?cfg_threshold:active_threshold;
    wire [1:0] pre_mode=grad_ctl[3]?cfg_preprocess:active_pre;
    wire [15:0] radius=(pre_mode==0)?16'd1:(QUALITY_FILTER_ENABLE?16'd3:16'd2);
    wire interior=(ex>=radius && ex<WIDTH-radius && ey>=radius && ey<HEIGHT-radius);
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) input_coords(
        .clk(clk),.rst_n(rst_n),.de(in_de),.vs(in_vs),.x(ix),.y(iy),
        .sof(input_sof),.eol(unused_eol));
    img_rgb2gray gray_op(.clk(clk),.rst_n(rst_n),.rgb(in_rgb),.gray(gray));
    img_delay #(.BITS(4),.CYCLES(1)) gray_timing(
        .clk(clk),.rst_n(rst_n),.din(in_ctl),.dout(gray_ctl));
    img_delay #(.BITS(24),.CYCLES(1)) original_first(
        .clk(clk),.rst_n(rst_n),.din(in_rgb),.dout(rgb_d1));
    img_preprocess #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.QUALITY_FILTER_ENABLE(QUALITY_FILTER_ENABLE)) preprocess(
        .clk(clk),.rst_n(rst_n),.pixel(gray),.ctl(gray_ctl),.cfg_mode(cfg_preprocess),
        .out_pixel(pre_pixel),.out_ctl(pre_ctl));
    img_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) gradient_window(
        .clk(clk),.rst_n(rst_n),.de(pre_ctl[0]),.vs(pre_ctl[2]),.pixel(pre_pixel),
        .window(sobel_win),.window_valid(win_valid));
    img_delay #(.BITS(4),.CYCLES(WIN_DELAY)) window_timing(
        .clk(clk),.rst_n(rst_n),.din(pre_ctl),.dout(win_ctl));
    img_sobel_gradient gradient(.clk(clk),.rst_n(rst_n),.pixels(sobel_win),
        .gx(gx),.gy(gy),.magnitude(mag));
    img_gradient_direction gradient_normal(.gx(gx),.gy(gy),.direction(direction));
    img_delay #(.BITS(1),.CYCLES(4)) gradient_valid_d(
        .clk(clk),.rst_n(rst_n),.din(win_valid),.dout(gradient_valid));
    img_delay #(.BITS(4),.CYCLES(4)) gradient_timing(
        .clk(clk),.rst_n(rst_n),.din(win_ctl),.dout(grad_ctl));
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) edge_coords(
        .clk(clk),.rst_n(rst_n),.de(grad_ctl[0]),.vs(grad_ctl[2]),.x(ex),.y(ey),
        .sof(esof),.eol(eeol));
    always @(posedge clk) begin
        if (!rst_n) begin active_threshold<=0;active_pre<=0;edge_q<=0;mag_q<=0;direction_q<=0;valid_q<=0;low_q<=0;end
        else begin
            if (grad_ctl[3]) begin active_threshold<=cfg_threshold;active_pre<=cfg_preprocess;end
            edge_q<=grad_ctl[0] && gradient_valid && interior && mag>=threshold;
            mag_q<=(grad_ctl[0] && gradient_valid && interior)?mag:11'd0;
            direction_q<=direction;
            valid_q<=grad_ctl[0] && gradient_valid && interior;
            low_q<=grad_ctl[0] && gradient_valid && interior && {1'b0,mag}>=(({1'b0,threshold}+12'd1)>>1);
        end
    end
    img_delay #(.BITS(4),.CYCLES(1)) edge_timing(
        .clk(clk),.rst_n(rst_n),.din(grad_ctl),.dout(edge_ctl));
    // Carry RGB once; gray is exactly reproducible from this same RGB token.
    // Avoid storing its redundant 8 bits through five lines of delay RAM.
    img_delay #(.BITS(24),.CYCLES(TO_EDGE)) original_alignment(
        .clk(clk),.rst_n(rst_n),.din(rgb_d1),.dout(original_aligned));
    wire nms_keep;wire [10:0] nms_magnitude;wire [3:0] nms_ctl;
    wire [41:0] aligned;
    img_nms #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.STRICT_TIES(NMS_STRICT_TIES)) nms(
        .clk(clk),.rst_n(rst_n),.magnitude(mag_q),.direction(direction_q),
        .valid(valid_q),.ctl(edge_ctl),.keep(nms_keep),.out_magnitude(nms_magnitude),.out_ctl(nms_ctl));
    // Retain EXACT original threshold decision and M5 amplitude. NMS can
    // only suppress that same pixel; it does not change threshold or gain.
    // Carry cfg_display too, so its SOF sampling occurs on the same token
    // as the original C2 composer even while changing modes frame-to-frame.
    img_delay #(.BITS(42),.CYCLES(NMS_DELAY)) nms_alignment(
        .clk(clk),.rst_n(rst_n),.din({direction_q,low_q,cfg_display,original_aligned,mag_q,edge_q}),.dout(aligned));
    wire e1_edge=aligned[0] && (NMS_ENABLE?nms_keep:1'b1);
    wire linked;wire [3:0] linked_ctl;wire [38:0] linked_context;
    img_edge_link #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.MIN_SEEDS(LINK_MIN_SEEDS),.WEAK_CHAIN_ENABLE(WEAK_CHAIN_ENABLE)) linking(
        .clk(clk),.rst_n(rst_n),.descriptor({aligned[41:40],nms_keep&&aligned[0],nms_keep&&aligned[39],aligned[39]}),
        .ctl(nms_ctl),.edge_pixel(linked),.out_ctl(linked_ctl));
    img_delay #(.BITS(39),.CYCLES(LINK_DELAY)) link_alignment(
        .clk(clk),.rst_n(rst_n),.din({aligned[38:1],e1_edge}),.dout(linked_context));
    wire selected_edge=(LINK_ENABLE && NMS_ENABLE)?linked:linked_context[0];
    wire [7:0] final_gray;wire [43:0] final_token;
    img_rgb2gray gray_replay(.clk(clk),.rst_n(rst_n),.rgb(linked_context[35:12]),.gray(final_gray));
    img_delay #(.BITS(44),.CYCLES(1)) gray_replay_alignment(
        .clk(clk),.rst_n(rst_n),.din({linked_ctl,linked_context,selected_edge}),.dout(final_token));
    wire final_edge=final_token[0];
    img_composer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.PAIR_EDGE(COMPARE_PAIR_EDGE)) composer(
        .clk(clk),.rst_n(rst_n),.ctl(final_token[43:40]),.rgb(final_token[36:13]),
        .gray(final_gray),.edge_pixel(final_edge),.magnitude(final_token[12:2]),
        .cfg_display(final_token[39:37]),.out_rgb(out_rgb),.out_ctl(composed_ctl));
    assign {out_vs,out_hs,out_de}=composed_ctl[2:0];
    assign debug_magnitude=final_token[12:2];assign debug_edge=final_edge;
endmodule

`default_nettype wire
