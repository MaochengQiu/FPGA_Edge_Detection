`timescale 1ns/1ps
module tb_e8_delay;
    parameter integer BITS=42,CYCLES=2205;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [BITS-1:0] data=0;wire [BITS-1:0] actual,reference;
    img_delay #(.BITS(BITS),.CYCLES(CYCLES)) dut(.clk(clk),.rst_n(rst),.din(data),.dout(actual));
    img_delay_e7 #(.BITS(BITS),.CYCLES(CYCLES)) old(.clk(clk),.rst_n(rst),.din(data),.dout(reference));
    integer n,j,compared=0;reg [31:0] rng=32'h82164432;
    initial begin
        for(n=0;n<6*CYCLES+120;n=n+1)begin
            @(negedge clk);
            rst=n>=4 && n!=CYCLES/2+10 && n!=2*CYCLES+33 && n!=2*CYCLES+34;
            for(j=0;j<BITS;j=j+1)begin
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};data[j]=rng[0];
            end
            @(posedge clk);#1;
            if(actual!==reference)$fatal(1,"Delay mismatch bits%0d cycles%0d at%0d got%h want%h",BITS,CYCLES,n,actual,reference);
            compared=compared+1;
        end
        $display("E8 DELAY PASS BITS=%0d CYCLES=%0d %0d clocks, bank/tail/wrap/cold-fill/reset exact E7",BITS,CYCLES,compared);$finish;
    end
endmodule
