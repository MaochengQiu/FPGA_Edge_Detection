`timescale 1ns/1ps
module tb_e7_rgb_delay;
    localparam W=24,H=20,HT=32,L=6*HT+61;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg de=0,hs=0,vs=0;reg [1:0] pre=0;
    wire [23:0] out_rgb;wire od,oh,ov;
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(1),.LINK_ENABLE(1),.QUALITY_FILTER_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(11'd50),.cfg_display(3'd0),
        .out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    reg [26:0] queue[0:L-1];integer i,checked=0;
    always @(posedge clk)begin
        if(!rst)for(i=0;i<L;i=i+1)queue[i]<=0;
        else begin
            queue[0]<={vs,hs,de,(de?rgb:24'd0)};
            for(i=1;i<L;i=i+1)queue[i]<=queue[i-1];
            #1;
            if({ov,oh,od,out_rgb}!==queue[L-1])$fatal(1,"E7 RGB/control latency mismatch %0d",checked);
            checked=checked+1;
        end
    end
    integer f,x,y;reg [31:0] rng=32'h7621309;
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(f=0;f<8;f=f+1)begin
            pre=f%4;
            for(y=0;y<H+16;y=y+1)for(x=0;x<HT;x=x+1)begin
                @(negedge clk);de=y>=2 && y<H+2 && x<W;hs=x==W+2;vs=y==0;
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};rgb=rng[23:0];
            end
        end
        @(negedge clk);rgb=0;de=0;hs=0;vs=0;
        repeat(L+8)@(negedge clk);
        $display("E7 RGB PASS 8 PRE-changing frames: every RGB sample and sync matches common 6*HTOTAL+61 latency");$finish;
    end
    initial begin #1000000;$fatal(1,"RGB timeout");end
endmodule
