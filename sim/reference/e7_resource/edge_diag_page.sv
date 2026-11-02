`timescale 1ns/1ps
`default_nettype none
// V6: Three-line transparent, white HDMI telemetry overlay over LIVE VIDEO.
// Modes 0 (RGB), 3 (full-field split) and 6 (full-field RGB calibration).
// Other modes are unchanged. No frame store, no new clocks, no pin/IP changes.
// Values are derived from existing registered statistics and counters.
// White 5x7 text (2x scaling) with a 2px dark drop shadow, NO opaque panel.
// Out RGB and DE/HS/VS all have EXACTLY ONE registered clock of latency.
module edge_diag_page #(
    parameter integer WIDTH=1920, HEIGHT=1080
)(
    input wire clk,rst_n,de,hs,vs,
    input wire [23:0] in_rgb,
    input wire [2:0] display_mode,
    input wire [1:0] preprocess_mode,
    input wire [10:0] threshold,
    input wire [7:0] key_press_count,
    input wire [1:0] last_key,
    input wire [9:0] wb_r,wb_g,wb_b,
    input wire [1:0] wb_selected,
    input wire [7:0] mean_raw_r,mean_raw_g,mean_raw_b,
    input wire [7:0] mean_bal_r,mean_bal_g,mean_bal_b,
    input wire sample_valid,
    input wire [8:0] last_samples,
    input wire [7:0] cam_bcd,done_bcd,selected_bcd,
    input wire reject_flag,late_flag,overflow_flag,freeze_active,
    output reg [23:0] out_rgb,
    output reg out_de,out_hs,out_vs
);
    wire [15:0] x,y;
    wire sof_unused,eol_unused;
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) xy(
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),
        .x(x),.y(y),.sof(sof_unused),.eol(eol_unused));
    localparam integer LEFT=24, TOP=14, COLS=62, ROWS=3;
    wire [15:0] tx=x-LEFT, ty=y-TOP;
    wire [6:0] col=tx[10:4];
    wire [1:0] row=ty[5:4];
    wire [2:0] fx=tx[3:1];
    wire [2:0] fy=ty[3:1];
    wire overlay_mode=(display_mode==3'd0 || display_mode==3'd3 || display_mode==3'd6);
    wire overlay_area=overlay_mode && (WIDTH>=1050) && (HEIGHT>=80) && de &&
        (x>=LEFT && x<LEFT+COLS*16) && (y>=TOP && y<TOP+ROWS*16);
    reg [7:0] letter;
    function [7:0] hex_ascii(input [3:0] nib);
        begin hex_ascii=(nib<10)?(8'h30+{4'd0,nib}):(8'h41+{4'd0,nib}-8'd10);end
    endfunction
    function [34:0] font5(input [7:0] c);
        begin case(c)
            8'h20:font5=35'h000000000;
            8'h41:font5=35'h3a31fc631;
            8'h42:font5=35'h7a31f463e;
            8'h43:font5=35'h3e108420f;
            8'h44:font5=35'h7a318c63e;
            8'h45:font5=35'h7e10f421f;
            8'h46:font5=35'h7e10f4210;
            8'h47:font5=35'h3e10bc62f;
            8'h48:font5=35'h4631fc631;
            8'h49:font5=35'h7c842109f;
            8'h4a:font5=35'h1c4214a4c;
            8'h4b:font5=35'h4654c5251;
            8'h4c:font5=35'h42108421f;
            8'h4d:font5=35'h4775ac631;
            8'h4e:font5=35'h47359c631;
            8'h4f:font5=35'h3a318c62e;
            8'h50:font5=35'h7a31f4210;
            8'h51:font5=35'h3a318d64d;
            8'h52:font5=35'h7a31f5251;
            8'h53:font5=35'h3e107043e;
            8'h54:font5=35'h7c8421084;
            8'h55:font5=35'h46318c62e;
            8'h56:font5=35'h46318c544;
            8'h57:font5=35'h4631ad6aa;
            8'h58:font5=35'h462a22a31;
            8'h59:font5=35'h462a21084;
            8'h5a:font5=35'h7c222221f;
            8'h30:font5=35'h3a75ae62e;
            8'h31:font5=35'h11842108e;
            8'h32:font5=35'h3a211111f;
            8'h33:font5=35'h78217043e;
            8'h34:font5=35'h08ca97c42;
            8'h35:font5=35'h7e10f043e;
            8'h36:font5=35'h3a10f462e;
            8'h37:font5=35'h7c2222108;
            8'h38:font5=35'h3a317462e;
            8'h39:font5=35'h3a317842e;
            8'h3a:font5=35'h008401080;
            8'h2e:font5=35'h0000000c6;
            8'h2f:font5=35'h042222210;
            8'h2b:font5=35'h0084f9080;
            8'h2d:font5=35'h0000f8000;
            8'h3d:font5=35'h001f07c00;
            8'h28:font5=35'h088842082;
            8'h29:font5=35'h208210888;
            default:font5=0;
        endcase end
    endfunction
    always @* begin
        letter=8'h20;
        case({row,col})
            {2'd0,7'd0}: letter=8'h52;
            {2'd0,7'd1}: letter=8'h41;
            {2'd0,7'd2}: letter=8'h57;
            {2'd0,7'd4}: letter=8'h52;
            {2'd0,7'd5}: letter=8'h3a;
            {2'd0,7'd9}: letter=8'h47;
            {2'd0,7'd10}: letter=8'h3a;
            {2'd0,7'd14}: letter=8'h42;
            {2'd0,7'd15}: letter=8'h3a;
            {2'd0,7'd20}: letter=8'h4f;
            {2'd0,7'd21}: letter=8'h55;
            {2'd0,7'd22}: letter=8'h54;
            {2'd0,7'd24}: letter=8'h52;
            {2'd0,7'd25}: letter=8'h3a;
            {2'd0,7'd29}: letter=8'h47;
            {2'd0,7'd30}: letter=8'h3a;
            {2'd0,7'd34}: letter=8'h42;
            {2'd0,7'd35}: letter=8'h3a;
            {2'd0,7'd40}: letter=8'h4e;
            {2'd0,7'd41}: letter=8'h3a;
            {2'd0,7'd46}: letter=8'h56;
            {2'd0,7'd47}: letter=8'h3a;
            {2'd0,7'd6}: letter=hex_ascii((mean_raw_r >> 4) & 4'hF);
            {2'd0,7'd7}: letter=hex_ascii((mean_raw_r >> 0) & 4'hF);
            {2'd0,7'd11}: letter=hex_ascii((mean_raw_g >> 4) & 4'hF);
            {2'd0,7'd12}: letter=hex_ascii((mean_raw_g >> 0) & 4'hF);
            {2'd0,7'd16}: letter=hex_ascii((mean_raw_b >> 4) & 4'hF);
            {2'd0,7'd17}: letter=hex_ascii((mean_raw_b >> 0) & 4'hF);
            {2'd0,7'd26}: letter=hex_ascii((mean_bal_r >> 4) & 4'hF);
            {2'd0,7'd27}: letter=hex_ascii((mean_bal_r >> 0) & 4'hF);
            {2'd0,7'd31}: letter=hex_ascii((mean_bal_g >> 4) & 4'hF);
            {2'd0,7'd32}: letter=hex_ascii((mean_bal_g >> 0) & 4'hF);
            {2'd0,7'd36}: letter=hex_ascii((mean_bal_b >> 4) & 4'hF);
            {2'd0,7'd37}: letter=hex_ascii((mean_bal_b >> 0) & 4'hF);
            {2'd0,7'd42}: letter=hex_ascii((last_samples >> 8) & 4'hF);
            {2'd0,7'd43}: letter=hex_ascii((last_samples >> 4) & 4'hF);
            {2'd0,7'd44}: letter=hex_ascii((last_samples >> 0) & 4'hF);
            {2'd0,7'd48}: letter=hex_ascii((sample_valid >> 0) & 4'hF);
            {2'd1,7'd0}: letter=8'h47;
            {2'd1,7'd1}: letter=8'h41;
            {2'd1,7'd2}: letter=8'h49;
            {2'd1,7'd3}: letter=8'h4e;
            {2'd1,7'd5}: letter=8'h52;
            {2'd1,7'd6}: letter=8'h3a;
            {2'd1,7'd11}: letter=8'h47;
            {2'd1,7'd12}: letter=8'h3a;
            {2'd1,7'd17}: letter=8'h42;
            {2'd1,7'd18}: letter=8'h3a;
            {2'd1,7'd23}: letter=8'h53;
            {2'd1,7'd24}: letter=8'h45;
            {2'd1,7'd25}: letter=8'h4c;
            {2'd1,7'd26}: letter=8'h3a;
            {2'd1,7'd30}: letter=8'h54;
            {2'd1,7'd31}: letter=8'h3a;
            {2'd1,7'd36}: letter=8'h46;
            {2'd1,7'd37}: letter=8'h3a;
            {2'd1,7'd40}: letter=8'h4b;
            {2'd1,7'd41}: letter=8'h45;
            {2'd1,7'd42}: letter=8'h59;
            {2'd1,7'd43}: letter=8'h3a;
            {2'd1,7'd47}: letter=8'h4c;
            {2'd1,7'd48}: letter=8'h41;
            {2'd1,7'd49}: letter=8'h53;
            {2'd1,7'd50}: letter=8'h54;
            {2'd1,7'd51}: letter=8'h3a;
            {2'd1,7'd7}: letter=hex_ascii((wb_r >> 8) & 4'hF);
            {2'd1,7'd8}: letter=hex_ascii((wb_r >> 4) & 4'hF);
            {2'd1,7'd9}: letter=hex_ascii((wb_r >> 0) & 4'hF);
            {2'd1,7'd13}: letter=hex_ascii((wb_g >> 8) & 4'hF);
            {2'd1,7'd14}: letter=hex_ascii((wb_g >> 4) & 4'hF);
            {2'd1,7'd15}: letter=hex_ascii((wb_g >> 0) & 4'hF);
            {2'd1,7'd19}: letter=hex_ascii((wb_b >> 8) & 4'hF);
            {2'd1,7'd20}: letter=hex_ascii((wb_b >> 4) & 4'hF);
            {2'd1,7'd21}: letter=hex_ascii((wb_b >> 0) & 4'hF);
            {2'd1,7'd27}: letter=hex_ascii((wb_selected >> 0) & 4'hF);
            {2'd1,7'd32}: letter=hex_ascii((threshold >> 8) & 4'hF);
            {2'd1,7'd33}: letter=hex_ascii((threshold >> 4) & 4'hF);
            {2'd1,7'd34}: letter=hex_ascii((threshold >> 0) & 4'hF);
            {2'd1,7'd38}: letter=hex_ascii((preprocess_mode >> 0) & 4'hF);
            {2'd1,7'd44}: letter=hex_ascii((key_press_count >> 4) & 4'hF);
            {2'd1,7'd45}: letter=hex_ascii((key_press_count >> 0) & 4'hF);
            {2'd1,7'd52}: letter=hex_ascii((last_key >> 0) & 4'hF);
            {2'd2,7'd0}: letter=8'h43;
            {2'd2,7'd1}: letter=8'h41;
            {2'd2,7'd2}: letter=8'h4d;
            {2'd2,7'd3}: letter=8'h3a;
            {2'd2,7'd7}: letter=8'h44;
            {2'd2,7'd8}: letter=8'h44;
            {2'd2,7'd9}: letter=8'h52;
            {2'd2,7'd10}: letter=8'h3a;
            {2'd2,7'd14}: letter=8'h53;
            {2'd2,7'd15}: letter=8'h43;
            {2'd2,7'd16}: letter=8'h52;
            {2'd2,7'd17}: letter=8'h45;
            {2'd2,7'd18}: letter=8'h45;
            {2'd2,7'd19}: letter=8'h4e;
            {2'd2,7'd20}: letter=8'h3a;
            {2'd2,7'd25}: letter=8'h45;
            {2'd2,7'd26}: letter=8'h52;
            {2'd2,7'd27}: letter=8'h52;
            {2'd2,7'd29}: letter=8'h52;
            {2'd2,7'd30}: letter=8'h3a;
            {2'd2,7'd33}: letter=8'h4c;
            {2'd2,7'd34}: letter=8'h3a;
            {2'd2,7'd37}: letter=8'h4f;
            {2'd2,7'd38}: letter=8'h3a;
            {2'd2,7'd41}: letter=8'h48;
            {2'd2,7'd42}: letter=8'h4f;
            {2'd2,7'd43}: letter=8'h4c;
            {2'd2,7'd44}: letter=8'h44;
            {2'd2,7'd45}: letter=8'h3a;
            {2'd2,7'd4}: letter=hex_ascii((cam_bcd >> 4) & 4'hF);
            {2'd2,7'd5}: letter=hex_ascii((cam_bcd >> 0) & 4'hF);
            {2'd2,7'd11}: letter=hex_ascii((done_bcd >> 4) & 4'hF);
            {2'd2,7'd12}: letter=hex_ascii((done_bcd >> 0) & 4'hF);
            {2'd2,7'd21}: letter=hex_ascii((selected_bcd >> 4) & 4'hF);
            {2'd2,7'd22}: letter=hex_ascii((selected_bcd >> 0) & 4'hF);
            {2'd2,7'd31}: letter=hex_ascii((reject_flag >> 0) & 4'hF);
            {2'd2,7'd35}: letter=hex_ascii((late_flag >> 0) & 4'hF);
            {2'd2,7'd39}: letter=hex_ascii((overflow_flag >> 0) & 4'hF);
            {2'd2,7'd46}: letter=hex_ascii((freeze_active >> 0) & 4'hF);
            default:letter=8'h20;
        endcase
    end
    wire [34:0] bitmap=font5(letter);
    // Each font bit covers a 2x2 pixel square; drop shadow is offset +2,+2.
    wire ink=(fx>=1 && fx<=5 && fy<=6) &&
        bitmap[34-(fy*5+(fx-1))];
    wire shadow=(fx>=2 && fx<=6 && fy>=1 && fy<=7) &&
        bitmap[34-((fy-1)*5+(fx-2))];
    wire [23:0] current_rgb=(overlay_area && ink) ? 24'hFFFFFF :
                            (overlay_area && shadow) ? 24'h111820 : in_rgb;
    always @(posedge clk) begin
        if(!rst_n) begin
            out_rgb<=24'd0;
            out_de<=1'b0;out_hs<=1'b0;out_vs<=1'b0;
        end else begin
            out_rgb<=de?current_rgb:24'd0;
            out_de<=de;out_hs<=hs;out_vs<=vs;
        end
    end
endmodule
`default_nettype wire
