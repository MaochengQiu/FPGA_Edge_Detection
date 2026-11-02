`timescale 1ns/1ps
module tb_e8_equivalence;
    parameter integer WIDTH=32,HEIGHT=24,HTOTAL=40,FRAMES=32,HD=0;
    localparam integer LATENCY=6*HTOTAL+61;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg de=0,hs=0,vs=0;
    reg [2:0] mode=3;reg [1:0] pre=2;reg [10:0] threshold=50;
    wire [23:0] actual,reference;wire ad,ah,av,rd,rh,rv,ae,re,aso,rso;
    wire [10:0] am,rm;
    img_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),
        .NMS_ENABLE(1),.LINK_ENABLE(1),.QUALITY_FILTER_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(threshold),.cfg_display(mode),
        .out_rgb(actual),.out_de(ad),.out_hs(ah),.out_vs(av),.debug_edge(ae),.debug_magnitude(am),.input_sof(aso));
    e7_ref_img_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),
        .NMS_ENABLE(1),.LINK_ENABLE(1),.QUALITY_FILTER_ENABLE(1)) old(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(threshold),.cfg_display(mode),
        .out_rgb(reference),.out_de(rd),.out_hs(rh),.out_vs(rv),.debug_edge(re),.debug_magnitude(rm),.input_sof(rso));
    integer compared=0,active=0,edges=0,bank_wrap=0;
    always @(posedge clk)if(rst)begin
        #1;
        if({actual,ad,ah,av,ae,am,aso}!=={reference,rd,rh,rv,re,rm,rso})
            $fatal(1,"E8/E7 full core mismatch cycle%0d mode%0d pre%0d actual%h reference%h",compared,mode,pre,actual,reference);
        compared=compared+1;
        if(ad)active=active+1;
        if(ae)edges=edges+1;
    end
    integer f,x,y;reg [31:0] rng=32'h87471920;reg [7:0] g;
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(f=0;f<FRAMES;f=f+1)begin
            if(f==FRAMES/2)begin
                rst=0;repeat(4)@(negedge clk);rst=1;
            end
            mode=HD?((f==0)?2:((f==1)?3:7)):(f%8);
            pre=HD?(f%4):((f/8)%4);
            threshold=(f%3==0)?32:((f%3==1)?50:73);
            for(y=0;y<HEIGHT+18;y=y+1)for(x=0;x<HTOTAL;x=x+1)begin
                @(negedge clk);de=y>=2 && y<HEIGHT+2 && x<WIDTH;
                hs=x>=WIDTH+2 && x<WIDTH+4;vs=y==0;
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                case(f%3)
                    0:g=(x<WIDTH/2)?32:220;
                    1:g=((x/5+y/4)%2)?190:44;
                    2:g=rng[7:0];
                endcase
                rgb=de?((f%3==2)?rng[23:0]:{g,g,g}):0;
            end
        end
        @(negedge clk);rgb=0;de=0;hs=0;vs=0;
        repeat(LATENCY+12)@(negedge clk);
        if(active<1000 || edges==0)$fatal(1,"Missing active/edge coverage");
        $display("E8 CORE PASS W%0d H%0d HT%0d FRAMES%0d %0d exact E7 clocks, %0d active, %0d edge, all RGB/sync/magnitude/edge/SOF; mid-run reset",WIDTH,HEIGHT,HTOTAL,FRAMES,compared,active,edges);
        $finish;
    end
endmodule
