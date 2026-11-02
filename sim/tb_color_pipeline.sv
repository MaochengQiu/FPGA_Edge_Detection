`timescale 1ns/1ps
// Real C1 color stage + unchanged gray/Sobel/composer versus an independent
// integer color reference feeding the same unchanged algorithm kernel.
module tb_color_pipeline;
    localparam W=16,H=8,HT=22;
    reg clk=0,rst=0,de=0,hs=0,vs=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg [9:0] rg=192,gg=448,bg=240;
    wire [23:0] raw,balanced,actual,expected;
    wire bd,bh,bv,ad,ah,av,ed,eh,ev;wire [2:0] clip;
    reg [23:0] ref_rgb=0;reg rd=0,rh=0,rv=0,prev_vs=0;
    integer ar=256,ag=256,ab=256,checked=0;
    reg [1:0] pre=0;reg [2:0] mode=0;
    edge_color_balance wb(.clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .gain_r(rg),.gain_g(gg),.gain_b(bg),.raw_rgb(raw),.bal_rgb(balanced),.clipped_rgb(clip),
        .out_de(bd),.out_hs(bh),.out_vs(bv));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT)) real_pipe(.clk(clk),.rst_n(rst),
        .in_rgb(balanced),.in_de(bd),.in_hs(bh),.in_vs(bv),.cfg_preprocess(pre),.cfg_threshold(11'd24),.cfg_display(mode),
        .out_rgb(actual),.out_de(ad),.out_hs(ah),.out_vs(av));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT)) ref_pipe(.clk(clk),.rst_n(rst),
        .in_rgb(ref_rgb),.in_de(rd),.in_hs(rh),.in_vs(rv),.cfg_preprocess(pre),.cfg_threshold(11'd24),.cfg_display(mode),
        .out_rgb(expected),.out_de(ed),.out_hs(eh),.out_vs(ev));
    function [7:0] scale(input integer p,input integer g);
        integer q;begin q=(p*g+128)/256;scale=(q>255)?255:q;end
    endfunction
    always @(posedge clk)begin
        if(!rst)begin ref_rgb<=0;rd<=0;rh<=0;rv<=0;prev_vs<=0;ar=256;ag=256;ab=256;end
        else begin
            if(vs && !prev_vs)begin ar=rg;ag=gg;ab=bg;end
            prev_vs<=vs;
            ref_rgb<={scale(rgb[23:16],ar),scale(rgb[15:8],ag),scale(rgb[7:0],ab)};
            rd<=de;rh<=hs;rv<=vs;
            #1;
            if(balanced!==ref_rgb || {bd,bh,bv}!={rd,rh,rv})$fatal(1,"WB reference/alignment");
            if({actual,ad,ah,av}!=={expected,ed,eh,ev})$fatal(1,"C1 gray/Sobel/overlay alignment");
            checked=checked+1;
        end
    end
    integer f,x,y;reg [7:0] r,g,b;
    initial begin
        repeat(4)@(negedge clk);rst=1;
        for(f=0;f<32;f=f+1)begin
            pre=f%4;mode=f%6;rg=(f%2)?256:192;gg=(f%2)?256:448;bg=(f%2)?256:240;
            for(y=0;y<H+10;y=y+1)for(x=0;x<HT;x=x+1)begin
                de=y>=2 && y<H+2 && x<W;hs=x==W+2;vs=y==0;
                r=x*17+f;g=y*31+x*3;b=(x+y)*13;
                if(f%4==0)begin r=(x[1]^y[1])?255:0;g=r;b=r;end
                rgb={r,g,b};
                if(y==5 && x==3)begin rg=128;gg=576;bg=576;end
                @(negedge clk);
            end
        end
        de=0;hs=0;vs=0;repeat(5*HT+64)@(negedge clk);
        if(checked<12000)$fatal(1,"short color pipeline test");
        $display("COLOR PIPELINE PASS %0d samples, color/checker/ramp, all preprocesses, RGB/gray/Sobel/split/overlay, unchanged timing",checked);$finish;
    end
    initial begin #1000000;$fatal(1,"color pipeline timeout");end
endmodule
