`timescale 1ns/1ps
module tb_e3_controls;
    reg clk=0,rst=0,sof=0;
    always #5 clk=~clk;
    reg [2:0] keys=7;
    wire [1:0] pre;
    wire [2:0] display;
    wire [9:0] r,g,b;
    wire [1:0] phase;
    img_control #(.DEBOUNCE_CYCLES(5),.LONG_CYCLES(20),.THRESHOLD_DEFAULT(50)) dut(
        .clk(clk),.rst_n(rst),.keys_n(keys),.frame_sof(sof),
        .cfg_wr(1'b0),.cfg_addr(2'd0),.cfg_data(11'd0),
        .preprocess(pre),.display(display),.wb_r(r),.wb_g(g),.wb_b(b),.bayer_phase(phase));
    task cycles(input integer n);repeat(n)@(negedge clk);endtask
    task commit;begin sof=1;cycles(1);sof=0;cycles(2);end endtask
    integer k;
    initial begin
        cycles(4);rst=1;cycles(4);
        for(k=0;k<8;k=k+1)begin
            keys[2]=0;cycles(60);
            if(pre!=(k%4))$fatal(1,"preprocess changed before SOF");
            commit();
            if(pre!=((k+1)%4) || display!=3)$fatal(1,"long hold or wrap failed");
            cycles(60);commit();
            if(pre!=((k+1)%4))$fatal(1,"held key repeated");
            keys[2]=1;cycles(15);commit();
            if(display!=3)$fatal(1,"long release also changed display");
            if(r!=10'h240 || g!=10'h180 || b!=10'h240 || phase!=2)
                $fatal(1,"PRE operation disturbed confirmed color");
        end
        $display("E3 CONTROL PASS 8 long presses, PRE0..3 wrap, SOF commit, no hold repeat, color intact");
        $finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
