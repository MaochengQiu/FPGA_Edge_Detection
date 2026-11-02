`timescale 1ns/1ps
// Audit the EXISTING board Debayer using its effective GRBG input convention.
// This proves RTL lane order/width on known patterns, not the sensor's physical
// Bayer phase after crop/mirror. Physical phase still needs a color chart.
module tb_debayer_color;
    localparam W=32,H=10,HT=22;
    reg clk=0,rst=0,vs=0,hs=0,de=0;always #5 clk=~clk;
    reg [15:0] raw=0,gain=256;
    wire ov,oh,od,valid;wire [47:0] rgb;
    reg [7:0] er=0,eg=0,eb=0;
    integer ox=0,oy=0,checked=0,cases=0;
    integer pattern=0;
    reg [23:0] c0,c1;reg [47:0] expected_pair;
    reg prev_de=0,prev_vs=0;
    debayer_top_2to1 dut(.in_pclk(clk),.in_rstn(rst),
        .raw_vs_i(vs),.raw_hs_i(hs),.raw_de_i(de),.raw_valid_i(de),.raw_datax4_i(raw),
        .r_gain(gain),.g_gain(gain),.b_gain(gain),
        .rgb_vs_o(ov),.rgb_hs_o(oh),.rgb_de_o(od),.rgb_valid_o(valid),.rgb_datax2_o(rgb));
    function [23:0] image_rgb(input integer x,input integer y);
        integer band;reg [7:0] r,g,b;
        begin
            band=x/4;r=0;g=0;b=0;
            case(pattern)
                1:begin r=(band&1)?220:16;g=(band&2)?180:32;b=(band&4)?200:8;end
                2:begin r=((x/2+y/2)%2)?220:20;g=r;b=r;end
                3:begin r=x*5+y*3;g=x*2+y*7+11;b=x*3+y*9+29;end
                4:begin r=x%2?255:0;g=y%2?0:255;b=(x+y)%2?192:64;end
                5:begin r=x<W/2?24:192;g=y<5?16:200;b=x+y<W/2?140:64;end
            endcase
            image_rgb={r,g,b};
        end
    endfunction
    function [7:0] mosaic(input integer x,input integer y);
        reg [23:0] c;
        begin
            c=image_rgb(x,y);
            if(y%2==0)mosaic=(x%2==0)?c[15:8]:c[23:16];
            else mosaic=(x%2==0)?c[7:0]:c[15:8];
        end
    endfunction
    function [23:0] bilinear(input integer x,input integer y);
        integer r,g,b;
        begin
            if(y%2==0 && x%2==1)begin
                r=mosaic(x,y);g=(mosaic(x-1,y)+mosaic(x+1,y)+mosaic(x,y-1)+mosaic(x,y+1))/4;
                b=(mosaic(x-1,y-1)+mosaic(x+1,y-1)+mosaic(x-1,y+1)+mosaic(x+1,y+1))/4;
            end else if(y%2==1 && x%2==0)begin
                b=mosaic(x,y);g=(mosaic(x-1,y)+mosaic(x+1,y)+mosaic(x,y-1)+mosaic(x,y+1))/4;
                r=(mosaic(x-1,y-1)+mosaic(x+1,y-1)+mosaic(x-1,y+1)+mosaic(x+1,y+1))/4;
            end else begin
                g=mosaic(x,y);
                if(y%2==0)begin r=(mosaic(x-1,y)+mosaic(x+1,y))/2;b=(mosaic(x,y-1)+mosaic(x,y+1))/2;end
                else begin r=(mosaic(x,y-1)+mosaic(x,y+1))/2;b=(mosaic(x-1,y)+mosaic(x+1,y))/2;end
            end
            bilinear={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    always @(negedge clk)if(rst)begin
        if(ov && !prev_vs)begin ox=0;oy=0;end
        else begin
            if(od)begin
                if(oy>=3 && oy<H-1 && ox>=4 && ox<W/2-2)begin
                    expected_pair={eb,eg,er,eb,eg,er};
                    if(pattern!=0)begin
                        // Existing filter's center: one source row/pixel-pair
                        // earlier than output raster. C1 does not change this.
                        c0=bilinear(2*(ox-1),oy-1);c1=bilinear(2*(ox-1)+1,oy-1);
                        expected_pair={c1[7:0],c1[15:8],c1[23:16],c0[7:0],c0[15:8],c0[23:16]};
                    end
                    if(rgb!==expected_pair)
                        $fatal(1,"Debayer case=%0d pattern=%0d word=%0d row=%0d got=%h expected=%h",cases,pattern,ox,oy,rgb,expected_pair);
                    checked=checked+1;
                end
                ox=ox+1;
            end else ox=0;
            if(prev_de && !od)oy=oy+1;
        end
        if(od!==valid)$fatal(1,"Debayer DE/valid mismatch");
        prev_de=od;prev_vs=ov;
    end
    task field(input integer r,input integer g,input integer b);
        integer sy,x,y;reg [7:0] lo,hi;
        begin
            @(posedge clk);#1;
            er=(r*gain)>>8;eg=(g*gain)>>8;eb=(b*gain)>>8;cases=cases+1;
            for(sy=0;sy<H+4;sy=sy+1)for(x=0;x<HT;x=x+1)begin
                vs=sy==0;hs=x==0;de=sy>=2 && sy<H+2 && x<W/2;
                y=sy-2;
                lo=y[0]?b:g;hi=y[0]?g:r;
                if(pattern!=0)begin lo=mosaic(2*x,y);hi=mosaic(2*x+1,y);end
                raw={hi,lo};@(posedge clk);#1;
            end
            de=0;vs=0;hs=0;
        end
    endtask
    integer p;
    initial begin
        repeat(4)@(posedge clk);#1;rst=1;
        field(255,0,0);field(0,255,0);field(0,0,255);
        field(64,128,192);field(244,106,196);
        for(p=0;p<256;p=p+1)field(p,p,p);
        gain=255;field(255,255,255); // old 0x00ff fallback yields 254, not 255
        gain=256;
        for(pattern=1;pattern<=5;pattern=pattern+1)field(0,0,0);
        if(checked<10000)$fatal(1,"too few audit pixels");
        $display("DEBAYER COLOR PASS %0d fields, %0d interior 2-pixel words, RGB/neutral ramps, spatial bars/checker/ramps vs bilinear reference, Q8 unity",cases,checked);$finish;
    end
    initial begin #2000000;$fatal(1,"Debayer timeout");end
endmodule
