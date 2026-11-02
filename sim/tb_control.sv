`timescale 1ns/1ps
module tb_control;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;reg [2:0] keys=7;reg sof=0,wr=0;
    reg [1:0] addr=0;reg [10:0] data=0;
    wire [10:0] threshold,pending;wire [7:0] count;wire [1:0] last;wire [1:0] pre;wire [2:0] display;wire freeze;
    img_control #(.DEBOUNCE_CYCLES(5),.LONG_CYCLES(20)) dut(
        .clk(clk),.rst_n(rst_n),.keys_n(keys),.frame_sof(sof),
        .cfg_wr(wr),.cfg_addr(addr),.cfg_data(data),.threshold(threshold),
        .preprocess(pre),.display(display),.freeze(freeze),.pending_threshold(pending),
        .key_press_count(count),.last_key(last));
    task cycles(input integer n);repeat(n) @(negedge clk);endtask
    task write_cfg(input [1:0] a,input [10:0] d);
        begin addr=a;data=d;wr=1;cycles(1);wr=0;cycles(1);end
    endtask
    task commit;begin sof=1;#1;cycles(1);sof=0;cycles(1);end endtask
    integer page,expected_page;
    initial begin
        cycles(4);rst_n=1;cycles(3);
        if(threshold!=24 || pre!=0 || display!=3) $fatal(1,"defaults");
        write_cfg(0,127);
        if(threshold!=24) $fatal(1,"midframe update");
        commit();if(threshold!=127) $fatal(1,"SOF commit");
        // Short bounce must not generate a threshold event.
        keys[0]=0;cycles(2);keys[0]=1;cycles(3);keys[0]=0;cycles(2);keys[0]=1;cycles(10);
        if(pending!=127 || count!=0) $fatal(1,"bounce changed threshold or generated key event");
        keys[0]=0;cycles(12);keys[0]=1;cycles(12);
        if(pending!=128 || count!=1 || last!=1) $fatal(1,"KEY1 press feedback");
        write_cfg(0,1);keys[1]=0;cycles(12);keys[1]=1;cycles(12);
        if(pending!=4 || count!=2 || last!=2) $fatal(1,"KEY2 press feedback");
        keys[1:0]=0;cycles(35);if(!freeze) $fatal(1,"freeze chord");
        keys[1:0]=3;cycles(12);
        keys[2]=0;cycles(12);keys[2]=1;cycles(12);commit();
        if(display!=4 || last!=3) $fatal(1,"KEY3 short feedback");
        keys[2]=0;cycles(50);keys[2]=1;cycles(12);commit();
        if(pre!=1 || display!=4) $fatal(1,"long press must change pre exactly once");
        write_cfg(1,7);commit();if(pre!=1) $fatal(1,"invalid preprocess accepted");
        keys[1:0]=0;cycles(12);keys[1:0]=3;cycles(12);
        if(freeze) $fatal(1,"unfreeze");
        write_cfg(2,3);commit();expected_page=3;
        // Four complete page cycles include the reported sixth press and
        // every 6->0 wrap. No invalid page, freeze, or preprocess side effect.
        for(page=0;page<28;page=page+1)begin
            keys[2]=0;cycles(12);keys[2]=1;cycles(12);commit();
            expected_page=(expected_page==6)?0:expected_page+1;
            if(display!=expected_page || freeze || pre!=1)$fatal(1,"mode cycle %0d",page+1);
        end
        $display("CONTROL PASS key feedback/debounce/saturation/frame commit/chord/short/long/invalid modes");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
