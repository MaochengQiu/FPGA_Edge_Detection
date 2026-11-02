`timescale 1ns/1ps
`default_nettype none
// 16 x 16 fixed-grid samples spanning the CENTER HALF of the image.
// Sum exactly 256 samples per complete frame and report floor(sum/256).
// This is measured RGB888 light level, NOT a sensor AE/AWB register readback.
// Input raw and corrected RGB must be aligned to the SAME pixel and DE/VS.
module edge_rgb_statistics #(
    parameter integer WIDTH=1920,HEIGHT=1080
)(
    input wire clk,rst_n,de,vs,
    input wire [23:0] raw_rgb,balanced_rgb,
    input wire [2:0] clipped_rgb,
    output reg [7:0] mean_raw_r,mean_raw_g,mean_raw_b,
    output reg [7:0] mean_bal_r,mean_bal_g,mean_bal_b,
    output reg sample_valid,
    output reg [8:0] last_samples,
    output reg [8:0] clipped_r,clipped_g,clipped_b
);
    localparam integer STEPX=WIDTH/32, STEPY=HEIGHT/32;
    localparam integer FIRSTX=WIDTH/4+STEPX/2;
    localparam integer FIRSTY=HEIGHT/4+STEPY/2;
    wire [15:0] x,y;
    wire unused_sof,unused_eol;
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) xy (
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),
        .x(x),.y(y),.sof(unused_sof),.eol(unused_eol));
    wire [15:0] xs,ys;
    wire sample=de && xs && ys;
    reg [16:0] sum_rr,sum_rg,sum_rb,sum_br,sum_bg,sum_bb;
    reg [8:0] sample_count;
    reg [8:0] clip_sum_r,clip_sum_g,clip_sum_b;
    reg vs_q;
    wire frame_start=vs&&!vs_q;
    genvar n;
    wire [15:0] matches_x,matches_y;
    generate for(n=0;n<16;n=n+1)begin:sample_positions
        assign matches_x[n]=(x==(FIRSTX+n*STEPX));
        assign matches_y[n]=(y==(FIRSTY+n*STEPY));
    end endgenerate
    assign xs=matches_x;
    assign ys=matches_y;
    always @(posedge clk) begin
        if(!rst_n) begin
            vs_q<=0;sum_rr<=0;sum_rg<=0;sum_rb<=0;
            sum_br<=0;sum_bg<=0;sum_bb<=0;sample_count<=0;
            mean_raw_r<=0;mean_raw_g<=0;mean_raw_b<=0;
            mean_bal_r<=0;mean_bal_g<=0;mean_bal_b<=0;
            sample_valid<=0;last_samples<=0;
            clip_sum_r<=0;clip_sum_g<=0;clip_sum_b<=0;
            clipped_r<=0;clipped_g<=0;clipped_b<=0;
        end else begin
            vs_q<=vs;
            if(frame_start)begin
                last_samples<=sample_count;
                sample_valid<=(sample_count==9'd256);
                if(sample_count==9'd256)begin
                    mean_raw_r<=sum_rr[15:8];mean_raw_g<=sum_rg[15:8];mean_raw_b<=sum_rb[15:8];
                    mean_bal_r<=sum_br[15:8];mean_bal_g<=sum_bg[15:8];mean_bal_b<=sum_bb[15:8];
                    clipped_r<=clip_sum_r;clipped_g<=clip_sum_g;clipped_b<=clip_sum_b;
                end
                sum_rr<=0;sum_rg<=0;sum_rb<=0;
                sum_br<=0;sum_bg<=0;sum_bb<=0;sample_count<=0;
                clip_sum_r<=0;clip_sum_g<=0;clip_sum_b<=0;
            end else if(sample)begin
                if(sample_count!=9'h1ff)sample_count<=sample_count+1'b1;
                sum_rr<=sum_rr+{9'd0,raw_rgb[23:16]};
                sum_rg<=sum_rg+{9'd0,raw_rgb[15:8]};
                sum_rb<=sum_rb+{9'd0,raw_rgb[7:0]};
                sum_br<=sum_br+{9'd0,balanced_rgb[23:16]};
                sum_bg<=sum_bg+{9'd0,balanced_rgb[15:8]};
                sum_bb<=sum_bb+{9'd0,balanced_rgb[7:0]};
                clip_sum_r<=clip_sum_r+{8'd0,clipped_rgb[2]};
                clip_sum_g<=clip_sum_g+{8'd0,clipped_rgb[1]};
                clip_sum_b<=clip_sum_b+{8'd0,clipped_rgb[0]};
            end
        end
    end
endmodule
`default_nettype wire
