`timescale 1ns/1ps
`default_nettype none
// Fixed-rate raster, 2 RAW8 pixels/clock on this board. Data starvation never
// changes HS/VS/DE. Drop the remainder of a broken frame, find the next SOF,
// and restart pixels only at the next active-frame boundary (no shifted rows).
// The upstream display FIFO is the elastic store; do not reset it each VS.
module img_video_out #(
    parameter integer DATA_BITS=16,PIXELS_PER_CLOCK=2,
    WIDTH=1920,HEIGHT=1080,HFP=88,HSP=44,HBP=148,VFP=4,VSP=5,VBP=36
)(
    input wire clk,rst_n,
    input wire [DATA_BITS-1:0] in_data,
    input wire in_valid,in_sof,in_eol,output wire in_ready,
    output reg frame_request,
    output reg [DATA_BITS-1:0] out_data,
    output reg out_de,out_hs,out_vs,
    output reg underflow_sticky,
    output reg [31:0] underflow_frames,displayed_frames
);
    localparam integer H_ACTIVE=WIDTH/PIXELS_PER_CLOCK;
    localparam integer H_SYNC=HSP/PIXELS_PER_CLOCK;
    localparam integer H_START=(HSP+HBP)/PIXELS_PER_CLOCK;
    localparam integer H_TOTAL=(WIDTH+HFP+HSP+HBP)/PIXELS_PER_CLOCK;
    localparam integer V_START=VSP+VBP,V_TOTAL=HEIGHT+VFP+VSP+VBP;
    localparam integer HCW=$clog2(H_TOTAL),VCW=$clog2(V_TOTAL);
    reg [HCW-1:0] h;
    reg [VCW-1:0] v;
    reg frame_good,ever_started;
    wire active=h>=H_START && h<H_START+H_ACTIVE && v>=V_START && v<V_START+HEIGHT;
    wire first=active && h==H_START && v==V_START;
    wire line_last=h==H_START+H_ACTIVE-1;
    wire frame_last=line_last && v==V_START+HEIGHT-1;
    wire tag_ok=first?in_sof:!in_sof;
    wire take_pixel=active && (first || frame_good) && in_valid && tag_ok;
    wire pixel_ok=take_pixel && (in_eol==line_last);
    // Hold a future SOF while draining the damaged old frame. During blanking
    // within a healthy frame, preserve the next row rather than consuming it.
    assign in_ready=rst_n && (take_pixel || (!frame_good && !in_sof));
    always @(posedge clk) begin
        if(!rst_n) begin
            h<=0;v<=0;frame_good<=0;ever_started<=0;frame_request<=0;
            out_data<=0;out_de<=0;out_hs<=0;out_vs<=0;
            underflow_sticky<=0;underflow_frames<=0;displayed_frames<=0;
        end else begin
            if(h==H_TOTAL-1) begin
                h<=0;
                if(v==V_TOTAL-1)v<=0;else v<=v+1'b1;
            end else h<=h+1'b1;
            frame_request<=h==0 && v==0;
            out_hs<=h<H_SYNC;
            out_vs<=v<VSP;
            out_de<=active;
            out_data<=pixel_ok?in_data:{DATA_BITS{1'b0}};
            if(first) begin
                frame_good<=pixel_ok;
                if(pixel_ok)ever_started<=1;
                if(!pixel_ok && ever_started) begin
                    underflow_sticky<=1;underflow_frames<=underflow_frames+1'b1;
                end
            end else if(active && frame_good && !pixel_ok) begin
                frame_good<=0;underflow_sticky<=1;
                underflow_frames<=underflow_frames+1'b1;
            end
            if(active && frame_last) begin
                frame_good<=0;
                if(frame_good && pixel_ok)displayed_frames<=displayed_frames+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
