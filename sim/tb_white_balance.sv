`timescale 1ns/1ps
module tb_white_balance;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,de=0,hs=0,vs=0;
 reg [23:0] in_rgb=0;
 reg [9:0] r_gain=10'h100,g_gain=10'h100,b_gain=10'h100;
 wire [23:0] raw,bal;wire de_o,hs_o,vs_o;
 edge_color_balance dut(.clk(clk),.rst_n(rst_n),.in_rgb(in_rgb),
   .in_de(de),.in_hs(hs),.in_vs(vs),.gain_r(r_gain),.gain_g(g_gain),.gain_b(b_gain),
   .raw_rgb(raw),.bal_rgb(bal),.out_de(de_o),.out_hs(hs_o),.out_vs(vs_o));
 task tick;begin @(negedge clk);end endtask
 initial begin
   repeat(3)tick();rst_n=1;
   r_gain=10'h0c0;g_gain=10'h140;b_gain=10'h100;
   vs=1;tick();vs=0;
   de=1;hs=1;in_rgb={8'd100,8'd80,8'd120};tick();
   if(raw!={8'd100,8'd80,8'd120} || bal!={8'd75,8'd100,8'd120} || !de_o || !hs_o)
      $fatal(1,"RGB gain/alignment mismatch %h %h",raw,bal);
   // A new gain should not take effect until next VS.
   r_gain=10'h180;g_gain=10'h180;b_gain=10'h180;tick();
   if(bal!={8'd75,8'd100,8'd120})$fatal(1,"gain changed mid frame");
   vs=1;tick();vs=0;in_rgb={8'd255,8'd220,8'd200};tick();
   if(bal!==24'hffffff)$fatal(1,"saturating gain failed %h",bal);
   $display("BALANCE PASS gain, frame snapshot, saturation and control alignment");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
