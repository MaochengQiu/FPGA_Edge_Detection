`timescale 1ns/1ps
`default_nettype none
// Diagnostic-only 1080p60 raster. No camera, DDR, algorithm, or frame RAM.
// Same positive-sync geometry as the normal video output, at one pixel/clock.
module edge_hdmi_test_pattern #(
    parameter integer WIDTH=1920,HEIGHT=1080,HFP=88,HSP=44,HBP=148,
    VFP=4,VSP=5,VBP=36
)(input wire clk,rst_n,output reg [23:0] rgb,
  output reg de,hs,vs);
    localparam integer HT=WIDTH+HFP+HSP+HBP,VT=HEIGHT+VFP+VSP+VBP;
    localparam integer XS=HSP+HBP,YS=VSP+VBP;
    reg [$clog2(HT)-1:0] h;
    reg [$clog2(VT)-1:0] v;
    reg [7:0] frame;
    wire active=h>=XS && h<XS+WIDTH && v>=YS && v<YS+HEIGHT;
    wire [15:0] x=h-XS,y=v-YS;
    reg [23:0] pattern;
    always @* begin
        if(x<WIDTH/2)
            pattern=((x[3:0]==0)||(y[3:0]==0))?24'hffffff:24'h000000;
        else if(y<HEIGHT/2)begin
            if(x<WIDTH*5/8)pattern=24'hff0000;
            else if(x<WIDTH*6/8)pattern=24'h00ff00;
            else if(x<WIDTH*7/8)pattern=24'h0000ff;
            else pattern=24'hffffff;
        end else pattern=(x[3]^y[3])?24'hffffff:24'h000000;
        // Blinking patch establishes that a frozen image is not a live raster.
        if(x>=WIDTH-32 && y>=HEIGHT-32)pattern=frame[4]?24'hffffff:24'h404040;
    end
    always @(posedge clk)begin
        if(!rst_n)begin h<=0;v<=0;frame<=0;rgb<=0;de<=0;hs<=0;vs<=0;end
        else begin
            if(h==HT-1)begin
                h<=0;
                if(v==VT-1)begin v<=0;frame<=frame+1'b1;end else v<=v+1'b1;
            end else h<=h+1'b1;
            hs<=h<HSP;vs<=v<VSP;de<=active;rgb<=active?pattern:24'd0;
        end
    end
endmodule
`default_nettype wire
