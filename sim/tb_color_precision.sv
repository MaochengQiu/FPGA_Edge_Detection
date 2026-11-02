`timescale 1ns/1ps
module tb_color_precision;
    reg clk=0,rst=0,de=0,hs=0,vs=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg [9:0] rg=256,gg=256,bg=256;
    wire [23:0] raw,balanced;wire od,oh,ov;wire [2:0] clips;
    edge_color_balance dut(.clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .gain_r(rg),.gain_g(gg),.gain_b(bg),.raw_rgb(raw),.bal_rgb(balanced),
        .clipped_rgb(clips),.out_de(od),.out_hs(oh),.out_vs(ov));
    function [7:0] reference(input integer p,input integer g);
        integer q;begin q=(p*g+128)/256;reference=(q>255)?255:q;end
    endfunction
    integer gain,p,gr,gb,checked=0;
    reg [7:0] r,g,b;reg [23:0] expected;reg [2:0] expected_clip;
    initial begin
        repeat(4)@(negedge clk);rst=1;
        for(gain=0;gain<1024;gain=gain+1)begin
            rg=gain;gr=gain^85;gb=1023-gain;gg=gr;bg=gb;
            vs=1;de=0;@(negedge clk);vs=0;
            for(p=0;p<256;p=p+1)begin
                r=p;g=255-p;b=(p*29)%256;
                rgb={r,g,b};de=p%17!=0;hs=p%23==0;
                // Deliberately change inputs mid-frame; active gains must hold.
                if(p==100)begin rg=0;gg=0;bg=0;end
                expected={reference(r,gain),reference(g,gr),reference(b,gb)};
                expected_clip=de?{((r*gain+128)/256>255),((g*gr+128)/256>255),((b*gb+128)/256>255)}:3'd0;
                @(negedge clk);
                if(raw!==rgb || balanced!==expected || clips!==expected_clip || {od,oh,ov}!={de,hs,vs})
                    $fatal(1,"color precision g=%0d p=%0d got=%h expected=%h clips=%b/%b",gain,p,balanced,expected,clips,expected_clip);
                checked=checked+1;
            end
        end
        $display("COLOR PRECISION PASS %0d samples, every 8-bit input x 10-bit gain, rounding, saturation, clipping flags, frame hold, RGB/timing",checked);$finish;
    end
    initial begin #4000000;$fatal(1,"precision timeout");end
endmodule
