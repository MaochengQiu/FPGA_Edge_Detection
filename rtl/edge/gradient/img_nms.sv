`timescale 1ns/1ps
`default_nettype none
// Streaming four-direction non-maximum suppression. II=1; no backpressure.
// ctl and the center pixel have identical latency HTOTAL+5 clocks.
// Direction is the gradient NORMAL, y positive down: 0 E/W, 1 NW/SE,
// 2 N/S, 3 NE/SW. Full 11-bit L1 magnitudes are compared before display clip.
// Default plateau rule keeps a maximum that exceeds at least one neighbor.
// This avoids deleting digital-curve connections at equal maxima. A two-pixel
// ridge can remain. STRICT_TIES=1 picks one consistent side for finer lines.
// This is thinning only, not hysteresis tracing or a complete Canny detector.
module img_nms #(parameter integer WIDTH=1920,HEIGHT=1080,HTOTAL=2200,
    parameter STRICT_TIES=1'b0)(
    input wire clk,rst_n,
    input wire [10:0] magnitude,input wire [1:0] direction,
    input wire valid,input wire [3:0] ctl,
    output reg keep,output reg [10:0] out_magnitude,
    output wire [3:0] out_ctl
);
    localparam integer B=14,WIN_DELAY=HTOTAL+3;
    wire [9*B-1:0] win;wire win_valid;
    wire [B-1:0] center=win[4*B+:B];
    reg [B-1:0] preceding,following;
    reg [10:0] c_q,a_q,b_q;
    reg good_q;
    img_window3x3 #(.BITS(B),.WIDTH(WIDTH),.HEIGHT(HEIGHT)) neighborhood(
        .clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),
        .pixel({valid,direction,magnitude}),.window(win),.window_valid(win_valid));
    img_delay #(.BITS(4),.CYCLES(WIN_DELAY+2)) timing(
        .clk(clk),.rst_n(rst_n),.din(ctl),.dout(out_ctl));
    always @* begin
        case(center[12:11])
            0:begin preceding=win[3*B+:B];following=win[5*B+:B];end
            1:begin preceding=win[0*B+:B];following=win[8*B+:B];end
            2:begin preceding=win[1*B+:B];following=win[7*B+:B];end
            3:begin preceding=win[2*B+:B];following=win[6*B+:B];end
        endcase
    end
    wire peak=good_q && (c_q!=0) && c_q>=a_q &&
        (STRICT_TIES ? c_q>b_q : (c_q>=b_q && (c_q>a_q || c_q>b_q)));
    always @(posedge clk)begin
        if(!rst_n)begin
            c_q<=0;a_q<=0;b_q<=0;good_q<=0;keep<=0;out_magnitude<=0;
        end else begin
            // Per-neighbor validity prevents uninitialized RAM/frame borders
            // from becoming extrema. Invalid borders are never synthesized data.
            c_q<=center[10:0];a_q<=preceding[10:0];b_q<=following[10:0];
            good_q<=win_valid && center[13] && preceding[13] && following[13];
            keep<=peak;out_magnitude<=peak?c_q:11'd0;
        end
    end
endmodule
`default_nettype wire
