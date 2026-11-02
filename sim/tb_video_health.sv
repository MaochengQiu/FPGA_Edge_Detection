`timescale 1ns/1ps
module tb_video_health;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,vs=0,cam=0,done=0,rej=0,late=0,overflow=0,freeze=0;
    reg [23:0] rgb=24'h123456;
    wire [23:0] rendered;
    edge_video_health #(.WIDTH(160),.HEIGHT(36),.MEASURE_FRAMES(4)) dut(
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb(rgb),.display_mode(3'd2),
        .cam_event_async(cam),.done_event_async(done),
        .reject_event_async(rej),.late_event_async(late),
        .overflow_sticky_async(overflow),.freeze_active(freeze),.out_rgb(rendered));
    task tick(input integer n);repeat(n) @(negedge clk);endtask
    task vs_pulse;begin vs=1;tick(4);vs=0;tick(4);end endtask
    initial begin
        tick(5);rst_n=1;tick(8);
        if(rendered!==rgb) $fatal(1,"HUD must bypass nonactive region");
        cam=1;tick(5);cam=0;tick(5);cam=1;tick(5);
        done=1;tick(5);done=0;tick(5);
        rej=1;tick(5);late=1;overflow=1;tick(5);
        if(!dut.reject_sticky || !dut.late_sticky || !dut.os)
            $fatal(1,"diagnostic status CDC");
        vs_pulse();vs_pulse();vs_pulse();vs_pulse();
        if(dut.cam_report_tens!=0 || dut.cam_report_ones!=3 ||
           dut.done_report_tens!=0 || dut.done_report_ones!=2)
            $fatal(1,"camera/completed counters report error");
        if(dut.cam_ones!=0 || dut.done_ones!=0)
            $fatal(1,"counter reset");
        $display("VIDEO HEALTH PASS async events / counters / status / transparency");
        $finish;
    end
    initial begin #40000;$fatal(1,"timeout");end
endmodule
