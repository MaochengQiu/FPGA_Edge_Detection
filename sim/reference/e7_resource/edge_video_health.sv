`timescale 1ns/1ps
`default_nettype none
// V3 observational HUD, one pixel-combinational mux; no HDMI timing changes.
// Camera frame and successful AXI frame rates are measured per 60 output frames.
// For an HDMI 1080p60 signal the values are numerically frames/second.
// Each asynchronous pulse source is converted to a toggle at its source clock;
// only the toggle is synchronized, never a multi-bit binary counter.
module edge_video_health #(
    parameter integer WIDTH=1920, HEIGHT=1080, MEASURE_FRAMES=60
)(
    input wire clk,rst_n,de,vs,
    input wire [23:0] rgb,
    input wire [2:0] display_mode,
    input wire cam_event_async,done_event_async,selected_event_async,
    input wire [10:0] threshold_pending, input wire [7:0] key_press_count,
    input wire [1:0] last_key,
    input wire reject_event_async,late_event_async,overflow_sticky_async,freeze_active,
    output wire [7:0] cam_bcd,done_bcd,selected_bcd,
    output wire reject_flag,late_flag,overflow_flag,
    output reg [23:0] out_rgb
);
    localparam integer HALF=(WIDTH+1)/2;
    localparam integer WC=(MEASURE_FRAMES<2)?1:$clog2(MEASURE_FRAMES);
    reg [WC-1:0] vs_periods;
    reg vs_q;
    (* async_reg="true" *) reg cm,cs,dm,ds,sm,ss,rm,rs,lm,ls,om,os;
    reg cp,dp,sp,rp,lp;
    wire cam_tick=cs^cp,done_tick=ds^dp,select_tick=ss^sp;
    wire reject_tick=rs^rp,late_tick=ls^lp;
    reg reject_sticky,late_sticky;
    reg [3:0] cam_ones,cam_tens,done_ones,done_tens,sel_ones,sel_tens;
    reg [3:0] cam_report_ones,cam_report_tens,done_report_ones,done_report_tens,sel_report_ones,sel_report_tens;
    assign cam_bcd={cam_report_tens,cam_report_ones};
    assign done_bcd={done_report_tens,done_report_ones};
    assign selected_bcd={sel_report_tens,sel_report_ones};
    assign reject_flag=reject_sticky;
    assign late_flag=late_sticky;
    assign overflow_flag=os;
    wire vs_tick=vs && !vs_q;
    wire [15:0] x,y;wire unused_sof,unused_eol;
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) xy(
       .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),
       .x(x),.y(y),.sof(unused_sof),.eol(unused_eol)
    );
    always @(posedge clk) begin
        if(!rst_n) begin
            vs_periods<=0;vs_q<=0;
            cm<=0;cs<=0;cp<=0;dm<=0;ds<=0;dp<=0;sm<=0;ss<=0;sp<=0;
            rm<=0;rs<=0;rp<=0;lm<=0;ls<=0;lp<=0;
            om<=0;os<=0;reject_sticky<=0;late_sticky<=0;
            cam_ones<=0;cam_tens<=0;done_ones<=0;done_tens<=0;sel_ones<=0;sel_tens<=0;
            cam_report_ones<=0;cam_report_tens<=0;
            done_report_ones<=0;done_report_tens<=0;sel_report_ones<=0;sel_report_tens<=0;
        end else begin
            cm<=cam_event_async;cs<=cm;cp<=cs;
            dm<=done_event_async;ds<=dm;dp<=ds;
            sm<=selected_event_async;ss<=sm;sp<=ss;
            rm<=reject_event_async;rs<=rm;rp<=rs;
            lm<=late_event_async;ls<=lm;lp<=ls;
            om<=overflow_sticky_async;os<=om;
            vs_q<=vs;
            if(reject_tick) reject_sticky<=1'b1;
            if(late_tick) late_sticky<=1'b1;
            if(vs_tick && vs_periods==MEASURE_FRAMES-1) begin
                vs_periods<=0;
                cam_report_ones<=cam_ones;cam_report_tens<=cam_tens;
                done_report_ones<=done_ones;done_report_tens<=done_tens;
                sel_report_ones<=sel_ones;sel_report_tens<=sel_tens;
                cam_ones<=0;cam_tens<=0;done_ones<=0;done_tens<=0;sel_ones<=0;sel_tens<=0;
            end else begin
                if(vs_tick) vs_periods<=vs_periods+1'b1;
                if(cam_tick && !(cam_ones==9 && cam_tens==9)) begin
                    if(cam_ones==9) begin cam_ones<=0;cam_tens<=cam_tens+1'b1;end
                    else cam_ones<=cam_ones+1'b1;
                end
                if(select_tick && !(sel_ones==9 && sel_tens==9)) begin
                    if(sel_ones==9) begin sel_ones<=0;sel_tens<=sel_tens+1'b1;end
                    else sel_ones<=sel_ones+1'b1;
                end
                if(done_tick && !(done_ones==9 && done_tens==9)) begin
                    if(done_ones==9) begin done_ones<=0;done_tens<=done_tens+1'b1;end
                    else done_ones<=done_ones+1'b1;
                end
            end
        end
    end
    // 7-segment bitmap a b c d e f g. 10='C', 11='d' label.
    function [6:0] glyph_bits(input [4:0] digit);
        begin
            case(digit)
              0:glyph_bits=7'b1111110; 1:glyph_bits=7'b0110000;
              2:glyph_bits=7'b1101101; 3:glyph_bits=7'b1111001;
              4:glyph_bits=7'b0110011; 5:glyph_bits=7'b1011011;
              6:glyph_bits=7'b1011111; 7:glyph_bits=7'b1110000;
              8:glyph_bits=7'b1111111; 9:glyph_bits=7'b1111011;
             10:glyph_bits=7'b1001110;11:glyph_bits=7'b0111101;
             12:glyph_bits=7'b0001111; // t: threshold (hex)
             13:glyph_bits=7'b1100111; // P: press count (hex)
             14:glyph_bits=7'b0011111; // b: last physical button
             15:glyph_bits=7'b1011011; // S: selected new display frames
             16:glyph_bits=7'b1110111; // A
             17:glyph_bits=7'b0011111; // b
             18:glyph_bits=7'b1001110; // C
             19:glyph_bits=7'b0111101; // d
             20:glyph_bits=7'b1001111; // E
             21:glyph_bits=7'b1000111; // F
           default:glyph_bits=0;
            endcase
        end
    endfunction
    function glyph_pixel(input [4:0] digit,input [4:0] px,input [4:0] py);
        reg [6:0] seg;
        begin
            seg=glyph_bits(digit);
            glyph_pixel=(seg[6] && py<=2 && px>=3 && px<=10) ||
               (seg[5] && px>=11 && px<=13 && py>=2 && py<=10) ||
               (seg[4] && px>=11 && px<=13 && py>=11 && py<=19) ||
               (seg[3] && py>=19 && py<=21 && px>=3 && px<=10) ||
               (seg[2] && px<=2 && py>=11 && py<=19) ||
               (seg[1] && px<=2 && py>=2 && py<=10) ||
               (seg[0] && py>=9 && py<=12 && px>=3 && px<=10);
        end
    endfunction
    wire right_half=x>=HALF;
    wire [15:0] lx=right_half?(x-HALF):x;
    wire [3:0] first_digit=right_half?4'd11:4'd10;
    wire [3:0] tens=right_half?done_report_tens:cam_report_tens;
    wire [3:0] ones=right_half?done_report_ones:cam_report_ones;
    wire [23:0] rate_color=(tens>=3)?24'h40ffc0:
                    (tens>=2)?24'hffe274:24'hff7060;
    wire g0=(lx>=12 && lx<26) && glyph_pixel(first_digit,lx-12,y[4:0]-5'd3);
    wire g1=(lx>=34 && lx<48) && glyph_pixel(tens,lx-34,y[4:0]-5'd3);
    wire g2=(lx>=52 && lx<66) && glyph_pixel(ones,lx-52,y[4:0]-5'd3);
    // Debug values are DISPLAYED, not inferred from edge density.
    // Threshold is shown as three hexadecimal digits (e.g. t028 = 40 decimal).
    function [4:0] hex_glyph(input [3:0] nib);
        begin hex_glyph=(nib<10)?{1'b0,nib}:({1'b0,nib}+5'd6);end
    endfunction
    wire [4:0] th_hi=hex_glyph({1'b0,threshold_pending[10:8]});
    wire [4:0] th_mid=hex_glyph(threshold_pending[7:4]);
    wire [4:0] th_lo=hex_glyph(threshold_pending[3:0]);
    wire [4:0] pc_hi=hex_glyph(key_press_count[7:4]);
    wire [4:0] pc_lo=hex_glyph(key_press_count[3:0]);
    // Compact white text overlay handles modes 0,3,6. Suppress the
    // old opaque V4 mini-HUD there, retaining it in legacy modes 1,2,4,5.
    wire legacy_hud_visible=(display_mode!=3'd0 && display_mode!=3'd3 && display_mode!=3'd6);
    wire hud_left = WIDTH>=650 && de && y>=3 && y<27 && !right_half;
    wire hud_right= WIDTH>=650 && de && y>=3 && y<27 && right_half;
    wire [4:0] py=y[4:0]-5'd3;
    wire tp=(lx>=112 && lx<126) && glyph_pixel(5'd12,lx-112,py);
    wire th0=(lx>=132 && lx<146) && glyph_pixel(th_hi,lx-132,py);
    wire th1=(lx>=150 && lx<164) && glyph_pixel(th_mid,lx-150,py);
    wire th2=(lx>=168 && lx<182) && glyph_pixel(th_lo,lx-168,py);
    wire kp=(lx>=207 && lx<221) && glyph_pixel(5'd13,lx-207,py);
    wire ke0=(lx>=229 && lx<243) && glyph_pixel(pc_hi,lx-229,py);
    wire ke1=(lx>=247 && lx<261) && glyph_pixel(pc_lo,lx-247,py);
    wire bl=(lx>=282 && lx<296) && glyph_pixel(5'd14,lx-282,py);
    wire bn=(lx>=300 && lx<314) && glyph_pixel({3'd0,last_key},lx-300,py);
    wire sl=(lx>=112 && lx<126) && glyph_pixel(5'd15,lx-112,py);
    wire st=(lx>=134 && lx<148) && glyph_pixel({1'b0,sel_report_tens},lx-134,py);
    wire so=(lx>=152 && lx<166) && glyph_pixel({1'b0,sel_report_ones},lx-152,py);
    always @* begin
        out_rgb=rgb;
        if(legacy_hud_visible && WIDTH>=160 && HEIGHT>=30 && de && y>=3 && y<27 && lx>=9 && lx<105) begin
            out_rgb=24'h101a27;
            if(g0 || g1 || g2) out_rgb=rate_color;
            // Persistent diagnostic markers: AXI rejected frame, late DMA request,
            // camera capture FIFO overflow. Flag state survives until board reset.
            if(lx>=72 && lx<77 && y>=10 && y<20 && reject_sticky)
                out_rgb=24'hff3030;
            if(lx>=79 && lx<84 && y>=10 && y<20 && late_sticky)
                out_rgb=24'hffa830;
            if(lx>=86 && lx<90 && y>=10 && y<20 && os)
                out_rgb=24'hff30dc;
            if(lx>=95 && lx<102 && y>=10 && y<20 && freeze_active)
                out_rgb=24'hffff00;
        end
        if(legacy_hud_visible && hud_left && lx>=108 && lx<322) begin
            out_rgb=24'h101a27;
            if(tp || th0 || th1 || th2 || kp || ke0 || ke1 || bl || bn)
                out_rgb=24'h98ecff;
        end
        if(legacy_hud_visible && hud_right && lx>=108 && lx<175) begin
            out_rgb=24'h101a27;
            if(sl || st || so) out_rgb=24'h98ecff;
        end
    end
endmodule
`default_nettype wire
