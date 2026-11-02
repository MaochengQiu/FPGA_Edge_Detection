`timescale 1ns/1ps
module tb_threshold_limits;
    reg clk=0,rst=0,sof=0,wr=0;always #5 clk=~clk;
    reg [2:0] keys=7;reg [1:0] addr=0;reg [10:0] data=0;
    wire [10:0] threshold,pending;wire [2:0] display;wire freeze;
    img_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(20),.REPEAT_DELAY_CYCLES(12),.REPEAT_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst),.keys_n(keys),.frame_sof(sof),.cfg_wr(wr),.cfg_addr(addr),.cfg_data(data),
        .threshold(threshold),.pending_threshold(pending),.display(display),.freeze(freeze));
    task pause(input integer n);repeat(n)@(negedge clk);endtask
    task cfg(input integer t);begin data=t;wr=1;pause(1);wr=0;pause(1);end endtask
    task commit;begin sof=1;pause(1);sof=0;pause(1);end endtask
    task tap(input integer k);begin keys[k]=0;pause(8);keys[k]=1;pause(8);end endtask
    integer t;
    always @(posedge clk)if(rst)begin
        #1;if(pending<4 || pending>128 || threshold<4 || threshold>128)$fatal(1,"limit violation");
    end
    initial begin
        pause(4);rst=1;pause(3);
        tap(0);if(pending!=25 || threshold!=24)$fatal(1,"single-step/frame atomicity");
        commit();if(threshold!=25)$fatal(1,"commit");
        // All host values, including values far beyond the practical range.
        for(t=0;t<2048;t=t+1)begin
            cfg(t);
            if(pending!=((t<4)?4:((t>128)?128:t)))$fatal(1,"config clamp %0d",t);
        end
        tap(0);tap(0);if(pending!=128)$fatal(1,"extra presses wrapped at MAX");
        cfg(24);commit();keys[0]=0;pause(600);keys[0]=1;pause(12);
        if(pending!=128 || threshold!=24)$fatal(1,"held increase saturation/frame update");
        commit();keys[1]=0;pause(600);keys[1]=1;pause(12);commit();
        if(pending!=4 || threshold!=4)$fatal(1,"held decrease saturation");
        tap(1);if(pending!=4)$fatal(1,"extra decrease wrapped");
        cfg(24);keys[1:0]=0;pause(100);
        if(!freeze || pending!=24)$fatal(1,"freeze chord changed threshold");
        keys=7;pause(12);
        $display("THRESHOLD LIMITS PASS +/-1, all config writes, held repeats, MAX/MIN saturation, frame commit, freeze");$finish;
    end
    initial begin #1000000;$fatal(1,"threshold timeout");end
endmodule
