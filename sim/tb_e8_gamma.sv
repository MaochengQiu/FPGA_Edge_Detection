`timescale 1ns/1ps
module tb_e8_gamma;
    parameter integer DATA_WIDTH=8;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg valid=0,hs=0,vs=0;
    reg [DATA_WIDTH-1:0] r=0,g=0,b=0;
    wire [DATA_WIDTH-1:0] ar,ag,ab,er,eg,eb;
    wire av,ah,as,ev,eh,es;
    reg [9:0] model[1023:0];
    gamma_correction #(.DATA_WIDTH(DATA_WIDTH),.GAMMA_CURVE("gamma.mem")) dut(
        .i_pclk(clk),.i_rstn(rst),.i_valid(valid),.i_hs(hs),.i_vs(vs),.i_red(r),.i_green(g),.i_blue(b),
        .o_red(ar),.o_green(ag),.o_blue(ab),.o_valid(av),.o_hs(ah),.o_vs(as));
    gamma_correction_e7 #(.DATA_WIDTH(DATA_WIDTH),.GAMMA_CURVE("gamma.mem")) old(
        .i_pclk(clk),.i_rstn(rst),.i_valid(valid),.i_hs(hs),.i_vs(vs),.i_red(r),.i_green(g),.i_blue(b),
        .o_red(er),.o_green(eg),.o_blue(eb),.o_valid(ev),.o_hs(eh),.o_vs(es));
    function [DATA_WIDTH-1:0] lookup(input [DATA_WIDTH-1:0] value);
        if(DATA_WIDTH==10)lookup=model[value];else lookup=model[{value,value[7:6]}]>>2;
    endfunction
    reg [DATA_WIDTH-1:0] mr,mg,mb;integer n,known=0,unknown_old_startup=0;
    reg [31:0] rng=32'h81281024;
    initial begin
        $readmemh("gamma.mem",model,0,1023);
        for(n=0;n<17000;n=n+1)begin
            @(negedge clk);rst=n>=4 && n!=6000 && n!=6001 && n!=10000;
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            valid=n%17!=0;hs=n%11==0;vs=n%103==0;
            r=n;g=n*73+51;b=rng;
            mr=(rst&&valid)?lookup(r):0;mg=(rst&&valid)?lookup(g):0;mb=(rst&&valid)?lookup(b):0;
            @(posedge clk);#1;
            if({ar,ag,ab}!=={mr,mg,mb})$fatal(1,"Gamma ROM oracle mismatch width%0d cycle%0d",DATA_WIDTH,n);
            if({av,ah,as}!=={(rst&&valid),(rst&&hs),(rst&&vs)})$fatal(1,"Gamma control/reset/latency");
            if({av,ah,as}!=={ev,eh,es})$fatal(1,"Gamma E7 sync differs");
            if(^{er,eg,eb}===1'bx)begin
                if(n>1040)$fatal(1,"E7 reference unexpectedly undefined after warmup");
                unknown_old_startup=unknown_old_startup+1;
            end else begin
                if({ar,ag,ab}!=={er,eg,eb})$fatal(1,"Gamma differs from defined E7 pixel width%0d cycle%0d got%h/%h/%h want%h/%h/%h",DATA_WIDTH,n,ar,ag,ab,er,eg,eb);
                known=known+1;
            end
        end
        $display("E8 GAMMA PASS WIDTH=%0d 17000 clocks; %0d defined E7 RGB comparisons; %0d undefined E7 startup cycles; exhaustive byte/10bit addresses, reset, blanking",DATA_WIDTH,known,unknown_old_startup);$finish;
    end
endmodule
