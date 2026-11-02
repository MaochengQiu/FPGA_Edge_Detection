`timescale 1ns/1ps
module tb_rgb_statistics;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,de=0,vs=0;
 reg [23:0] raw=0,balanced=0;
 wire [7:0] rr,rg,rb,br,bg,bb;wire valid;wire [8:0] count;
 wire [8:0] cr,cg,cb;reg [2:0] clip=0;
 edge_rgb_statistics #(.WIDTH(64),.HEIGHT(64)) dut(
   .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.raw_rgb(raw),.balanced_rgb(balanced),
   .clipped_rgb(clip),.clipped_r(cr),.clipped_g(cg),.clipped_b(cb),
   .mean_raw_r(rr),.mean_raw_g(rg),.mean_raw_b(rb),
   .mean_bal_r(br),.mean_bal_g(bg),.mean_bal_b(bb),
   .sample_valid(valid),.last_samples(count));
 integer y,x;
 initial begin
   repeat(4)@(negedge clk);rst_n=1;
   vs=1;@(negedge clk);vs=0;
   for(y=0;y<64;y=y+1)begin
      for(x=0;x<64;x=x+1)begin
        de=1;raw={8'd100,8'd80,8'd120};balanced={8'd75,8'd100,8'd120};
        clip={1'b1,(x<32),(y<32)};
        @(negedge clk);
      end
      de=0;@(negedge clk);
   end
   vs=1;@(negedge clk);vs=0;@(negedge clk);
   if(!valid || count!=256 || {rr,rg,rb}!={8'd100,8'd80,8'd120}
      || {br,bg,bb}!={8'd75,8'd100,8'd120})
      $fatal(1,"sample statistic mismatch count=%d raw=%h %h %h",count,rr,rg,rb);
   if(cr!=256 || cg!=128 || cb!=128)$fatal(1,"clip counts %0d %0d %0d",cr,cg,cb);
   $display("RGB STATS PASS 256 ROI samples, means, per-channel gain-clipping counts 256/128/128");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
