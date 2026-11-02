`timescale 1ns/1ps
module tb_weak_edges;
    localparam W=16,H=8,HT=22;
    reg clk=0,rst=0,de=0,hs=0,vs=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg [10:0] threshold=40;
    wire [23:0] out_rgb;wire od,oh,ov;
    integer edges=0,n40,n24,n4,n128,nflat;
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT)) dut(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(2'd0),.cfg_threshold(threshold),.cfg_display(3'd2),
        .out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    always @(negedge clk)if(rst && od && out_rgb==24'hffffff)edges=edges+1;
    task image(input integer t,input integer a,input integer b,output integer count);
        integer x,y;reg [7:0] p;
        begin
            @(negedge clk);threshold=t;edges=0;
            for(y=0;y<H+12;y=y+1)for(x=0;x<HT;x=x+1)begin
                de=y>=2 && y<H+2 && x<W;hs=x==W+2;vs=y==0;
                p=(x<W/2)?a:b;rgb={p,p,p};@(negedge clk);
            end
            de=0;hs=0;vs=0;repeat(5*HT+62)@(negedge clk);count=edges;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        // Dark step delta=8: true Sobel magnitude is 4*8=32.
        image(40,16,24,n40);image(24,16,24,n24);image(4,16,24,n4);
        image(128,96,160,n128);image(4,16,16,nflat);
        if(n40!=0 || n24==0 || n4<n24 || n128==0 || nflat!=0)
            $fatal(1,"weak edge mismatch T40=%0d T24=%0d T4=%0d bright=%0d flat=%0d",n40,n24,n4,n128,nflat);
        $display("WEAK EDGES PASS dark delta8: T40=%0d T24=%0d T4=%0d; bright T128=%0d; flat=%0d",n40,n24,n4,n128,nflat);$finish;
    end
    initial begin #1000000;$fatal(1,"weak-edge timeout");end
endmodule
