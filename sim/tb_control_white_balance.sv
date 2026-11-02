`timescale 1ns/1ps
module tb_control_white_balance;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [2:0] keys_n=3'b111;reg frame_sof=0,cfg_wr=0;
 reg [1:0] cfg_addr=0;reg [10:0] cfg_data=0;
 wire [10:0] threshold,pending;wire [1:0] preprocess,selected;
 wire [2:0] display;wire freeze;wire [7:0] key_count;wire [1:0] last;
 wire [9:0] r,g,b;
 wire [1:0] phase;
 integer n;
 img_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(12)) dut(
   .clk(clk),.rst_n(rst_n),.keys_n(keys_n),.frame_sof(frame_sof),
   .cfg_wr(cfg_wr),.cfg_addr(cfg_addr),.cfg_data(cfg_data),
   .threshold(threshold),.preprocess(preprocess),.display(display),.freeze(freeze),
   .pending_threshold(pending),.key_press_count(key_count),.last_key(last),
   .wb_r(r),.wb_g(g),.wb_b(b),.wb_selected(selected),.bayer_phase(phase));
 task pause(input integer n);repeat(n)@(negedge clk);endtask
 task set_mode(input [2:0] m);begin cfg_addr=2;cfg_data=m;cfg_wr=1;pause(1);cfg_wr=0;frame_sof=1;pause(1);frame_sof=0;pause(1);end endtask
 task keypress(input integer n);begin keys_n[n]=0;pause(8);keys_n[n]=1;pause(8);end endtask
 initial begin
   pause(3);rst_n=1;pause(3);
   if(r!=10'h240||g!=10'h180||b!=10'h240||display!=3||phase!=2)$fatal(1,"C2.1 board preset defaults");
   set_mode(6);if(display!=6)$fatal(1,"diagnostic page not reachable");
   keypress(0);if(r!=10'h240 || pending!=24)$fatal(1,"red preset MAX overflow");
   keypress(1);if(r!=10'h238)$fatal(1,"red gain - change");
   keypress(0);if(r!=10'h240)$fatal(1,"red gain + change");
   keys_n[2]=0;pause(20);keys_n[2]=1;pause(9);
   if(selected!=1 || preprocess!=0)$fatal(1,"long KEY3 did not select G");
   keypress(0);if(g!=10'h188)$fatal(1,"green gain + change");
   set_mode(3);keypress(0);
   if(pending!=25 || g!=10'h188)$fatal(1,"threshold mode regression");
   set_mode(6);
   for(n=0;n<64;n=n+1)keypress(0);
   if(g!=10'h240 || pending!=25)$fatal(1,"gain MAX saturation");
   for(n=0;n<128;n=n+1)keypress(1);
   if(g!=10'h080 || pending!=25)$fatal(1,"gain MIN saturation");
   keys_n[2]=0;pause(20);keys_n[2]=1;pause(9);
   if(selected!=2)$fatal(1,"B selection");
   keypress(0);if(b!=10'h240)$fatal(1,"B preset MAX overflow");
   keypress(1);if(b!=10'h238)$fatal(1,"B gain trim down");
   keypress(0);if(b!=10'h240)$fatal(1,"B gain trim up");
   keys_n[2]=0;pause(20);keys_n[2]=1;pause(9);
   if(selected!=3)$fatal(1,"P selection");
   for(n=0;n<8;n=n+1)begin
       keypress(0);if(phase!=((n+3)%4))$fatal(1,"phase + wrap");
   end
   for(n=0;n<8;n=n+1)begin
       keypress(1);if(phase!=((9-n)%4))$fatal(1,"phase - wrap");
   end
   if(r!=10'h240||g!=10'h080||b!=10'h240||pending!=25)$fatal(1,"phase changed gains or threshold");
   keys_n[0]=0;keys_n[1]=0;pause(9);keys_n=3'b111;pause(9);
   if(!freeze||phase!=2)$fatal(1,"freeze chord changed phase");
   keys_n[2]=0;pause(20);keys_n[2]=1;pause(9);
   if(selected!=0)$fatal(1,"P to R selection");
   rst_n=0;pause(3);rst_n=1;pause(3);
   if(r!=10'h240||g!=10'h180||b!=10'h240||phase!=2||selected!=0||freeze||pending!=24||display!=3)$fatal(1,"reset did not restore C2.1 board preset");
   $display("CONTROL WB C2.1 PASS PH2, gains 240/180/240, MAX no wrap, 1/32 trim, R/G/B/P, phase wraps, freeze, threshold and reset");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
