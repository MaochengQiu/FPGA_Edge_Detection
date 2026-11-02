`timescale 1ns/1ps
module tb_e7_gaussian;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [199:0] pixels=0;wire [7:0] pixel;
    img_gaussian5x5 dut(.clk(clk),.rst_n(rst),.pixels(pixels),.pixel(pixel));
    integer i,k,r,c,total,expected,previous=0;integer weight[0:4];
    reg [31:0] rng=32'h71281468;
    initial begin
        weight[0]=1;weight[1]=4;weight[2]=6;weight[3]=4;weight[4]=1;
        repeat(3)@(negedge clk);rst=1;
        for(i=0;i<4096;i=i+1)begin
            total=0;
            for(k=0;k<25;k=k+1)begin
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                if(i==0)pixels[8*k+:8]=0;
                else if(i==1)pixels[8*k+:8]=255;
                else if(i<27)pixels[8*k+:8]=(k==i-2)?255:0;
                else pixels[8*k+:8]=rng[7:0];
                total=total+int'(pixels[8*k+:8])*weight[k/5]*weight[k%5];
            end
            expected=(total+128)/256;
            @(posedge clk);#1;
            if(pixel!==8'(previous))$fatal(1,"Gaussian5 arithmetic/latency %0d got%0d expected%0d",i,pixel,previous);
            previous=expected;@(negedge clk);
        end
        @(posedge clk);#1;if(pixel!==8'(previous))$fatal(1,"Gaussian5 flush");
        $display("E7 GAUSSIAN PASS 4096 windows including zero, all255, 25 impulses, full-range random; exact rounding, no overflow");$finish;
    end
endmodule
