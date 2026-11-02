`timescale 1ns/1ps
module tb_e5_controls;
    reg clk=0,rst=0,sof=0,wr=0;always #5 clk=~clk;
    reg [2:0] keys=7;reg [1:0] addr=0;reg [10:0] data=0;
    wire [2:0] mode;wire [10:0] t;wire [1:0] pre,phase;wire [9:0] r,g,b;
    img_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(30),.DISPLAY_MAX(7)) dut(
        .clk(clk),.rst_n(rst),.keys_n(keys),.frame_sof(sof),.cfg_wr(wr),.cfg_addr(addr),.cfg_data(data),
        .display(mode),.threshold(t),.preprocess(pre),.bayer_phase(phase),.wb_r(r),.wb_g(g),.wb_b(b));
    task cycles(input integer n);repeat(n)@(negedge clk);endtask
    task commit;begin sof=1;cycles(1);sof=0;cycles(2);end endtask
    task write_cfg(input [1:0] a,input [10:0] v);
        begin addr=a;data=v;wr=1;cycles(1);wr=0;cycles(1);end
    endtask
    integer n,expected=3;
    initial begin
        cycles(5);rst=1;cycles(4);
        write_cfg(0,58);write_cfg(1,1);commit();
        for(n=0;n<64;n=n+1)begin
            keys[2]=0;cycles(12);keys[2]=1;cycles(12);commit();expected=(expected+1)%8;
            if(mode!=expected || t!=58 || pre!=1)$fatal(1,"8-page cycle changed controls");
            if(r!=10'h240 || g!=10'h180 || b!=10'h240 || phase!=2)$fatal(1,"color altered by page7");
        end
        write_cfg(2,7);commit();if(mode!=7)$fatal(1,"M7 rejected");
        write_cfg(2,8);commit();if(mode!=7)$fatal(1,"invalid M8 accepted");
        $display("E5 CONTROL PASS 64 short presses across M0..7, T/PRE/color preserved, invalid page rejected");$finish;
    end
    initial begin #100000;$fatal(1,"control timeout");end
endmodule
