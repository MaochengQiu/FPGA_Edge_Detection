`timescale 1ns/1ps
`default_nettype none
// V10: LAST-STAGE HDMI HUD. Compact mode/decimal-threshold label on pages 0..5,
// full telemetry on page 6. Independent active-raster counters; 1 CLK
// pipeline for RGB and DE/HS/VS together. A 3-pixel white left-edge sentinel
// confirms that the NEW bitstream, not a stale outflow/*.bit, was loaded.
// Parameters below are pixel-derived/RTL counters; NOT sensor AWB register reads.
module edge_final_hud #(
    parameter integer WIDTH=1920, HEIGHT=1080,THRESHOLD_MIN=4,THRESHOLD_MAX=128,THRESHOLD_STEP=1,
    parameter NMS_ENABLE=1'b1,LINK_ENABLE=1'b1,WEAK_CHAIN_ENABLE=1'b0,TEST_PATTERN=1'b0,PALETTE_PROBE=1'b0,DVI_TRANSPORT=1'b0,QUALITY_FILTER=1'b0,RESOURCE_OPT=1'b0
)(
    input wire clk,rst_n, in_de,in_hs,in_vs,
    input wire [23:0] in_rgb,
    input wire [7:0] mean_raw_r,mean_raw_g,mean_raw_b,
    input wire [7:0] mean_bal_r,mean_bal_g,mean_bal_b,
    input wire [8:0] last_samples,
    input wire sample_valid,
    input wire [8:0] clipped_r,clipped_g,clipped_b,
    input wire [9:0] wb_r,wb_g,wb_b, input wire [1:0] wb_selected,
    input wire [1:0] bayer_phase,
    input wire [10:0] threshold,
    input wire [2:0] display_mode,
    input wire [1:0] preprocess_mode,
    input wire [7:0] key_press_count,
    input wire [1:0] last_key,
    input wire [7:0] cam_bcd,done_bcd,selected_bcd,
    input wire reject_flag,late_flag,overflow_flag,freeze_active,
    input wire underflow_flag,read_error_flag,
    output reg [23:0] out_rgb,
    output reg out_de,out_hs,out_vs
);
    reg [15:0] x,y;
    reg prev_de,prev_vs;
    reg [7:0] frame_heartbeat;
    always @(posedge clk) begin
        if (!rst_n) begin
            x<=0;y<=0;prev_de<=0;prev_vs<=0;frame_heartbeat<=0;
        end else begin
            prev_de<=in_de;
            prev_vs<=in_vs;
            if (in_vs && !prev_vs) begin
                x<=0;y<=0;frame_heartbeat<=frame_heartbeat+1'b1;
            end else begin
                if (in_de) begin
                    if(x>=WIDTH-1) x<=0;
                    else x<=x+1'b1;
                end else x<=0;
                if (prev_de && !in_de) begin
                    if (y>=HEIGHT-1) y<=0;
                    else y<=y+1'b1;
                end
            end
        end
    end
    localparam integer ORIGIN_X=16, ORIGIN_Y=12;
    localparam integer COLS=64, ROWS=4;
    localparam integer CELL_W=16, CELL_H=18;
    wire hud_enabled=(display_mode==3'd6);
    wire tuning_label=!hud_enabled;
    wire at_max=threshold>=THRESHOLD_MAX,at_min=threshold<=THRESHOLD_MIN;
    wire area=in_de && x>=ORIGIN_X && x<ORIGIN_X+COLS*CELL_W &&
        y>=ORIGIN_Y && y<ORIGIN_Y+ROWS*CELL_H;
    wire [15:0] local_x=x-ORIGIN_X,local_y=y-ORIGIN_Y;
    wire [6:0] col=local_x[10:4];
    wire [1:0] row=(local_y<18)?2'd0:((local_y<36)?2'd1:((local_y<54)?2'd2:2'd3));
    wire [3:0] cx=local_x[3:0];
    wire [15:0] row_y=(local_y<18)?local_y:((local_y<36)?local_y-16'd18:((local_y<54)?local_y-16'd36:local_y-16'd54));
    wire [4:0] cy=row_y[4:0];
    function [7:0] hex_ascii(input [3:0] nib);
        begin
            hex_ascii=(nib<10)?8'h30+{4'd0,nib}:8'h41+{4'd0,nib}-8'd10;
        end
    endfunction

    function [7:0] phase_ascii(input [1:0] phase,input [1:0] index);
        reg [31:0] name;
        begin
            case(phase)
                0:name="GRBG";1:name="RGGB";2:name="BGGR";3:name="GBRG";
            endcase
            case(index)
                0:phase_ascii=name[31:24];1:phase_ascii=name[23:16];
                2:phase_ascii=name[15:8];3:phase_ascii=name[7:0];
            endcase
        end
    endfunction

    // Decimal conversion runs for 11 clocks only when the setting changes.
    // No divider and no decimal arithmetic in the per-pixel font path.
    reg [11:0] threshold_bcd;
    reg [10:0] bcd_source;
    reg [22:0] bcd_shift,bcd_adjusted;
    reg [3:0] bcd_left;
    reg bcd_started;
    integer digit;
    always @* begin
        bcd_adjusted=bcd_shift;
        for(digit=0;digit<3;digit=digit+1)
            if(bcd_shift[11+digit*4+:4]>=5)
                bcd_adjusted[11+digit*4+:4]=bcd_shift[11+digit*4+:4]+4'd3;
    end
    wire [22:0] bcd_next={bcd_adjusted[21:0],1'b0};
    always @(posedge clk)begin
        if(!rst_n)begin threshold_bcd<=0;bcd_source<=0;bcd_shift<=0;bcd_left<=0;bcd_started<=0;end
        else if(bcd_left!=0)begin
            bcd_shift<=bcd_next;bcd_left<=bcd_left-1'b1;
            if(bcd_left==1)threshold_bcd<=bcd_next[22:11];
        end else if(!bcd_started || bcd_source!=threshold)begin
            bcd_source<=threshold;bcd_shift<={12'd0,threshold};bcd_left<=11;bcd_started<=1;
        end
    end
    localparam [3:0] MAX_HUNDREDS=(THRESHOLD_MAX/100)%10;
    localparam [3:0] MAX_TENS=(THRESHOLD_MAX/10)%10,MAX_ONES=THRESHOLD_MAX%10;
    localparam [3:0] STEP_DIGIT=THRESHOLD_STEP;

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
    reg [7:0] letter;
    always @* begin
        letter=8'h20;
        case({row,col})
            {2'd0,7'd0}: letter=8'h45;
            {2'd0,7'd1}: letter=RESOURCE_OPT?8'h47:(QUALITY_FILTER?8'h37:(DVI_TRANSPORT?8'h36:(PALETTE_PROBE?8'h35:8'h34)));
            {2'd0,7'd2}: letter=RESOURCE_OPT?8'h52:(QUALITY_FILTER?8'h51:(DVI_TRANSPORT?8'h44:(PALETTE_PROBE?8'h41:(TEST_PATTERN?8'h54:8'h44))));
            {2'd0,7'd3}: letter=8'h20;
            {2'd0,7'd4}: letter=8'h20;
            {2'd0,7'd5}: letter=8'h20;
            {2'd0,7'd7}: letter=8'h52;
            {2'd0,7'd8}: letter=8'h3A;
            {2'd0,7'd9}: letter=hex_ascii((mean_raw_r >> 4) & 4'hf);
            {2'd0,7'd10}: letter=hex_ascii((mean_raw_r >> 0) & 4'hf);
            {2'd0,7'd12}: letter=8'h47;
            {2'd0,7'd13}: letter=8'h3A;
            {2'd0,7'd14}: letter=hex_ascii((mean_raw_g >> 4) & 4'hf);
            {2'd0,7'd15}: letter=hex_ascii((mean_raw_g >> 0) & 4'hf);
            {2'd0,7'd17}: letter=8'h42;
            {2'd0,7'd18}: letter=8'h3A;
            {2'd0,7'd19}: letter=hex_ascii((mean_raw_b >> 4) & 4'hf);
            {2'd0,7'd20}: letter=hex_ascii((mean_raw_b >> 0) & 4'hf);
            {2'd0,7'd23}: letter=8'h4F;
            {2'd0,7'd24}: letter=8'h55;
            {2'd0,7'd25}: letter=8'h54;
            {2'd0,7'd27}: letter=8'h52;
            {2'd0,7'd28}: letter=8'h3A;
            {2'd0,7'd29}: letter=hex_ascii((mean_bal_r >> 4) & 4'hf);
            {2'd0,7'd30}: letter=hex_ascii((mean_bal_r >> 0) & 4'hf);
            {2'd0,7'd32}: letter=8'h47;
            {2'd0,7'd33}: letter=8'h3A;
            {2'd0,7'd34}: letter=hex_ascii((mean_bal_g >> 4) & 4'hf);
            {2'd0,7'd35}: letter=hex_ascii((mean_bal_g >> 0) & 4'hf);
            {2'd0,7'd37}: letter=8'h42;
            {2'd0,7'd38}: letter=8'h3A;
            {2'd0,7'd39}: letter=hex_ascii((mean_bal_b >> 4) & 4'hf);
            {2'd0,7'd40}: letter=hex_ascii((mean_bal_b >> 0) & 4'hf);
            {2'd0,7'd43}: letter=8'h4E;
            {2'd0,7'd44}: letter=8'h3A;
            {2'd0,7'd45}: letter=hex_ascii((last_samples >> 8) & 4'hf);
            {2'd0,7'd46}: letter=hex_ascii((last_samples >> 4) & 4'hf);
            {2'd0,7'd47}: letter=hex_ascii((last_samples >> 0) & 4'hf);
            {2'd0,7'd49}: letter=8'h56;
            {2'd0,7'd50}: letter=8'h3A;
            {2'd0,7'd51}: letter=hex_ascii((sample_valid >> 0) & 4'hf);
            {2'd1,7'd0}: letter=8'h47;
            {2'd1,7'd1}: letter=8'h41;
            {2'd1,7'd2}: letter=8'h49;
            {2'd1,7'd3}: letter=8'h4E;
            {2'd1,7'd5}: letter=8'h52;
            {2'd1,7'd6}: letter=8'h3A;
            {2'd1,7'd7}: letter=hex_ascii((wb_r >> 8) & 4'hf);
            {2'd1,7'd8}: letter=hex_ascii((wb_r >> 4) & 4'hf);
            {2'd1,7'd9}: letter=hex_ascii((wb_r >> 0) & 4'hf);
            {2'd1,7'd11}: letter=8'h47;
            {2'd1,7'd12}: letter=8'h3A;
            {2'd1,7'd13}: letter=hex_ascii((wb_g >> 8) & 4'hf);
            {2'd1,7'd14}: letter=hex_ascii((wb_g >> 4) & 4'hf);
            {2'd1,7'd15}: letter=hex_ascii((wb_g >> 0) & 4'hf);
            {2'd1,7'd17}: letter=8'h42;
            {2'd1,7'd18}: letter=8'h3A;
            {2'd1,7'd19}: letter=hex_ascii((wb_b >> 8) & 4'hf);
            {2'd1,7'd20}: letter=hex_ascii((wb_b >> 4) & 4'hf);
            {2'd1,7'd21}: letter=hex_ascii((wb_b >> 0) & 4'hf);
            {2'd1,7'd24}: letter=8'h54;
            {2'd1,7'd25}: letter=8'h3A;
            {2'd1,7'd26}: letter=hex_ascii(threshold_bcd[11:8]);
            {2'd1,7'd27}: letter=hex_ascii(threshold_bcd[7:4]);
            {2'd1,7'd28}: letter=hex_ascii(threshold_bcd[3:0]);
            {2'd1,7'd30}: letter=8'h4D;
            {2'd1,7'd31}: letter=8'h4F;
            {2'd1,7'd32}: letter=8'h44;
            {2'd1,7'd33}: letter=8'h45;
            {2'd1,7'd34}: letter=8'h3A;
            {2'd1,7'd35}: letter=hex_ascii((display_mode >> 0) & 4'hf);
            {2'd1,7'd37}: letter=8'h4B;
            {2'd1,7'd38}: letter=8'h45;
            {2'd1,7'd39}: letter=8'h59;
            {2'd1,7'd40}: letter=8'h3A;
            {2'd1,7'd41}: letter=hex_ascii((key_press_count >> 4) & 4'hf);
            {2'd1,7'd42}: letter=hex_ascii((key_press_count >> 0) & 4'hf);
            {2'd1,7'd44}: letter=8'h53; // SEL:R/G/B
            {2'd1,7'd45}: letter=8'h45;
            {2'd1,7'd46}: letter=8'h4C;
            {2'd1,7'd47}: letter=8'h3A;
            {2'd1,7'd48}: letter=(wb_selected==0)?8'h52:((wb_selected==1)?8'h47:((wb_selected==2)?8'h42:8'h50));
            {2'd1,7'd50}: letter=8'h50;
            {2'd1,7'd51}: letter=8'h52;
            {2'd1,7'd52}: letter=8'h45;
            {2'd1,7'd53}: letter=8'h3a;
            {2'd1,7'd54}: letter=hex_ascii({2'd0,preprocess_mode});
            {2'd2,7'd0}: letter=8'h43;
            {2'd2,7'd1}: letter=8'h41;
            {2'd2,7'd2}: letter=8'h4D;
            {2'd2,7'd3}: letter=8'h3A;
            {2'd2,7'd4}: letter=hex_ascii((cam_bcd >> 4) & 4'hf);
            {2'd2,7'd5}: letter=hex_ascii((cam_bcd >> 0) & 4'hf);
            {2'd2,7'd7}: letter=8'h44;
            {2'd2,7'd8}: letter=8'h44;
            {2'd2,7'd9}: letter=8'h52;
            {2'd2,7'd10}: letter=8'h3A;
            {2'd2,7'd11}: letter=hex_ascii((done_bcd >> 4) & 4'hf);
            {2'd2,7'd12}: letter=hex_ascii((done_bcd >> 0) & 4'hf);
            {2'd2,7'd14}: letter=8'h53;
            {2'd2,7'd15}: letter=8'h43;
            {2'd2,7'd16}: letter=8'h52;
            {2'd2,7'd17}: letter=8'h45;
            {2'd2,7'd18}: letter=8'h45;
            {2'd2,7'd19}: letter=8'h4E;
            {2'd2,7'd20}: letter=8'h3A;
            {2'd2,7'd21}: letter=hex_ascii((selected_bcd >> 4) & 4'hf);
            {2'd2,7'd22}: letter=hex_ascii((selected_bcd >> 0) & 4'hf);
            {2'd2,7'd24}: letter=8'h45;
            {2'd2,7'd25}: letter=8'h52;
            {2'd2,7'd26}: letter=8'h52;
            {2'd2,7'd27}: letter=8'h3A;
            {2'd2,7'd28}: letter=8'h52;
            {2'd2,7'd29}: letter=hex_ascii((reject_flag >> 0) & 4'hf);
            {2'd2,7'd30}: letter=8'h4C;
            {2'd2,7'd31}: letter=hex_ascii((late_flag >> 0) & 4'hf);
            {2'd2,7'd32}: letter=8'h4F;
            {2'd2,7'd33}: letter=hex_ascii((overflow_flag >> 0) & 4'hf);
            {2'd2,7'd35}: letter=8'h46;
            {2'd2,7'd36}: letter=8'h52;
            {2'd2,7'd37}: letter=8'h5A;
            {2'd2,7'd38}: letter=8'h3A;
            {2'd2,7'd39}: letter=hex_ascii((freeze_active >> 0) & 4'hf);
            {2'd2,7'd41}: letter=8'h55; // U: video starvation
            {2'd2,7'd42}: letter=8'h3A;
            {2'd2,7'd43}: letter=hex_ascii({3'd0,underflow_flag});
            {2'd2,7'd45}: letter=8'h44; // D: AXI read error
            {2'd2,7'd46}: letter=8'h3A;
            {2'd2,7'd47}: letter=hex_ascii({3'd0,read_error_flag});
            {2'd3,7'd0}: letter=8'h45; // E1N/E1S RAW1X CLIP, color preset unchanged.
            {2'd3,7'd1}: letter=RESOURCE_OPT?8'h47:(QUALITY_FILTER?8'h37:(DVI_TRANSPORT?8'h36:(PALETTE_PROBE?8'h35:8'h34)));
            {2'd3,7'd2}: letter=RESOURCE_OPT?8'h52:(QUALITY_FILTER?8'h51:(DVI_TRANSPORT?8'h44:(PALETTE_PROBE?8'h41:(TEST_PATTERN?8'h54:8'h44))));
            {2'd3,7'd3}: letter=8'h20;
            {2'd3,7'd5}: letter=8'h52;
            {2'd3,7'd6}: letter=8'h41;
            {2'd3,7'd7}: letter=8'h57;
            {2'd3,7'd8}: letter=8'h31;
            {2'd3,7'd9}: letter=8'h58;
            {2'd3,7'd11}: letter=8'h43;
            {2'd3,7'd12}: letter=8'h4C;
            {2'd3,7'd13}: letter=8'h49;
            {2'd3,7'd14}: letter=8'h50;
            {2'd3,7'd16}: letter=8'h52;
            {2'd3,7'd17}: letter=8'h3A;
            {2'd3,7'd18}: letter=hex_ascii({3'd0,clipped_r[8]});
            {2'd3,7'd19}: letter=hex_ascii(clipped_r[7:4]);
            {2'd3,7'd20}: letter=hex_ascii(clipped_r[3:0]);
            {2'd3,7'd22}: letter=8'h47;
            {2'd3,7'd23}: letter=8'h3A;
            {2'd3,7'd24}: letter=hex_ascii({3'd0,clipped_g[8]});
            {2'd3,7'd25}: letter=hex_ascii(clipped_g[7:4]);
            {2'd3,7'd26}: letter=hex_ascii(clipped_g[3:0]);
            {2'd3,7'd28}: letter=8'h42;
            {2'd3,7'd29}: letter=8'h3A;
            {2'd3,7'd30}: letter=hex_ascii({3'd0,clipped_b[8]});
            {2'd3,7'd31}: letter=hex_ascii(clipped_b[7:4]);
            {2'd3,7'd32}: letter=hex_ascii(clipped_b[3:0]);
            {2'd3,7'd35}: letter=8'h50;
            {2'd3,7'd36}: letter=8'h48;
            {2'd3,7'd37}: letter=8'h3a;
            {2'd3,7'd38}: letter=hex_ascii({2'd0,bayer_phase});
            {2'd3,7'd40}: letter=phase_ascii(bayer_phase,2'd0);
            {2'd3,7'd41}: letter=phase_ascii(bayer_phase,2'd1);
            {2'd3,7'd42}: letter=phase_ascii(bayer_phase,2'd2);
            {2'd3,7'd43}: letter=phase_ascii(bayer_phase,2'd3);
            {2'd3,7'd45}: letter=8'h56;
            {2'd3,7'd46}: letter=8'h3a;
            {2'd3,7'd47}: letter=hex_ascii(frame_heartbeat[7:4]);
            {2'd3,7'd48}: letter=hex_ascii(frame_heartbeat[3:0]);
            {2'd3,7'd50}: letter=8'h4b;
            {2'd3,7'd51}: letter=8'h3a;
            {2'd3,7'd52}: letter=hex_ascii({2'd0,last_key});
            default: letter=8'h20;
        endcase
        if(tuning_label) begin
            letter=8'h20;
            if(row==0)case(col)
                0:letter=8'h56;1:letter=8'h31;2:letter=8'h30;
                4:letter=8'h4D;5:letter=8'h3A;6:letter=hex_ascii({1'b0,display_mode});
                8:letter=8'h54;9:letter=8'h3A;
                10:letter=hex_ascii(threshold_bcd[11:8]);
                11:letter=hex_ascii(threshold_bcd[7:4]);12:letter=hex_ascii(threshold_bcd[3:0]);
                14:letter=8'h4D;15:letter=8'h41;16:letter=8'h58;17:letter=8'h3A;
                18:letter=hex_ascii(MAX_HUNDREDS);19:letter=hex_ascii(MAX_TENS);20:letter=hex_ascii(MAX_ONES);
                22:letter=8'h53;23:letter=8'h3A;24:letter=hex_ascii(STEP_DIGIT);
                26:letter=at_max?8'h4D:(at_min?8'h4D:8'h20);
                27:letter=at_max?8'h41:(at_min?8'h49:8'h20);
                28:letter=at_max?8'h58:(at_min?8'h4E:8'h20);
                30:letter=8'h45;31:letter=RESOURCE_OPT?8'h47:(QUALITY_FILTER?8'h37:(DVI_TRANSPORT?8'h36:(PALETTE_PROBE?8'h35:8'h34)));32:letter=RESOURCE_OPT?8'h52:(QUALITY_FILTER?8'h51:(DVI_TRANSPORT?8'h44:(PALETTE_PROBE?8'h41:(TEST_PATTERN?8'h54:8'h44))));33:letter=8'h20;
                35:letter=8'h50;36:letter=8'h48;37:letter=8'h3a;
                38:letter=hex_ascii({2'd0,bayer_phase});
                40:letter=8'h50;41:letter=8'h52;42:letter=8'h45;43:letter=8'h3a;
                44:letter=hex_ascii({2'd0,preprocess_mode});
                default:letter=8'h20;
            endcase
            if(row==1)case(col)
                0:letter=8'h43;1:letter=8'h3a;2:letter=hex_ascii(cam_bcd[7:4]);3:letter=hex_ascii(cam_bcd[3:0]);
                5:letter=8'h42;6:letter=8'h3a;7:letter=hex_ascii(done_bcd[7:4]);8:letter=hex_ascii(done_bcd[3:0]);
                10:letter=8'h53;11:letter=8'h3a;12:letter=hex_ascii(selected_bcd[7:4]);13:letter=hex_ascii(selected_bcd[3:0]);
                15:letter=8'h55;16:letter=8'h3a;17:letter=hex_ascii({3'd0,underflow_flag});
                19:letter=8'h44;20:letter=8'h3a;21:letter=hex_ascii({3'd0,read_error_flag});
                23:letter=8'h52;24:letter=8'h3a;25:letter=hex_ascii({3'd0,reject_flag});
                27:letter=8'h4c;28:letter=8'h3a;29:letter=hex_ascii({3'd0,late_flag});
                31:letter=8'h4f;32:letter=8'h3a;33:letter=hex_ascii({3'd0,overflow_flag});
                35:letter=8'h46;36:letter=8'h3a;37:letter=hex_ascii({3'd0,freeze_active});
                39:letter=8'h4b;40:letter=8'h3a;41:letter=hex_ascii(key_press_count[7:4]);42:letter=hex_ascii(key_press_count[3:0]);
                44:letter=8'h4c;45:letter=8'h41;46:letter=8'h53;47:letter=8'h54;48:letter=8'h3a;49:letter=hex_ascii({2'd0,last_key});
                51:letter=8'h56;52:letter=8'h3a;53:letter=hex_ascii(frame_heartbeat[7:4]);54:letter=hex_ascii(frame_heartbeat[3:0]);
                default:letter=8'h20;
            endcase
        end
    end
    wire [34:0] bitmap=font5(letter);
    // 5x7 glyph enlarged 2x; no high-cost per-pixel division.
    wire visible_area=area && (hud_enabled || (row==0 && col<46) || (row==1 && col<56));
    wire letter_ink=visible_area && cx>=2 && cx<12 && cy>=2 && cy<16 &&
        bitmap[34-(((cy-2)>>1)*5 + ((cx-2)>>1))];
    wire sentinel=hud_enabled && in_de && x<3;
    // Last-stage fixed RGB/W/K references bypass sensor, gains and gamma.
    // Centers left-to-right must appear red, green, blue, white and black.
    wire reference_area=hud_enabled && in_de && x>=16 && x<336 && y>=92 && y<116;
    wire [23:0] reference_rgb=(x<80)?24'hff0000:((x<144)?24'h00ff00:
        ((x<208)?24'h0000ff:((x<272)?24'hffffff:24'h000000)));
    wire reference_border=reference_area && (y==92 || y==115 || x==16 || x==335);
    wire [23:0] mixed_rgb = sentinel ? 24'h00FFFF :
        reference_border ? 24'hffffff : reference_area ? reference_rgb :
        letter_ink ? ((tuning_label && at_max)?24'hFFCC40:24'hFFFFFF) :
        visible_area ? 24'h101821 : in_rgb;
    always @(posedge clk) begin
        if(!rst_n) begin
            out_rgb<=24'd0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            out_rgb<=in_de?mixed_rgb:24'd0;
            out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;
        end
    end
endmodule
`default_nettype wire
