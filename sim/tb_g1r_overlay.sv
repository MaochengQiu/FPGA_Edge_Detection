`timescale 1ns/1ps
module tb_g1r_overlay;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [3:0] ctl=0;reg [2:0] shape=0;reg edge_pixel=0;
 reg [3:0] reason=2;
 reg [63:0] tm=64'hffffffffffffffff,bm=64'hffffffffffffffff;
 reg [47:0] lm=48'hffffffffffff,rm=48'hffffffffffff;
 wire paint;wire [23:0] color;
 img_geometry_overlay #(.WIDTH(512),.HEIGHT(384)) dut(
  .clk(clk),.rst_n(rst),.ctl(ctl),.edge_pixel(edge_pixel),.shape(shape),
  .left(16'd192),.top(16'd144),.right(16'd319),.bottom(16'd271),
  .debug_reason(reason),.debug_cells(16'h1234),.debug_count(16'h0058),
  .debug_sides(32'h0e101010),.debug_radial(8'h22),
  .row_lo({48{8'd16}}),.row_hi({48{8'd47}}),.support_top(tm),.support_bottom(bm),.support_left(lm),.support_right(rm),.paint(paint),.color(color));
 integer f,x,y,green,amber,guide;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<5;f=f+1)begin
   @(negedge clk);ctl=4;shape=f;reason=f?0:2;
   tm=64'hffffffffffffffff;tm[30]=0;tm[31]=0;
   @(negedge clk);ctl=0;green=0;amber=0;guide=0;
   for(y=0;y<384;y=y+1)begin
    for(x=0;x<512;x=x+1)begin
     @(negedge clk);ctl=1;
     edge_pixel=(x==200 && y==145) || (x==196 && y==180) || (x==256 && y==180);
     #1;
     if(paint && color==24'h20ff40)green=green+1;
     if(paint && color==24'hffb020)amber=amber+1;
     if(paint && color==24'h606060)guide=guide+1;
     if(f==0 && y>=140 && x>=180 && x<=330 && paint)$fatal(1,"NONE drew false recognition box");
     if((f==2 || f==3) && x==248 && y==144 && (!paint || color!==24'hffb020))$fatal(1,"missing side not amber");
     if((f==2 || f==3) && x==252 && y==144 && paint)$fatal(1,"inferred side not dashed");
     if((f==2 || f==3) && x==200 && y==144 && (!paint || color!==24'h20ff40))$fatal(1,"supported side not green");
     if((f==2 || f==3) && x==200 && y==145 && (!paint || color!==24'h20ff40))$fatal(1,"live edge not green");
     if((f==1 || f==4) && x==196 && y==180 && (!paint || color!==24'h20ff40))$fatal(1,"curve edge not colored");
     if((f==1 || f==4) && x==256 && y==180 && paint)$fatal(1,"unrelated interior edge colored");
     if((f==1 || f==4) && x==255 && y==207 && (!paint || color!==24'h20ff40))$fatal(1,"circle marker absent");
     if(x==16 && y==56 && dut.letter!==8'h47)$fatal(1,"G1R marker missing");
     if(x==16 && y==74 && dut.letter!==8'h45)$fatal(1,"edge count label shifted");
     if(x==16 && y==92 && dut.letter!==8'h54)$fatal(1,"side count label shifted");
     if(x==16 && y==110 && dut.letter!==8'h57)$fatal(1,"width label shifted");
    end
    @(negedge clk);ctl=0;#1;if(paint)$fatal(1,"paint during blanking");
   end
   if(guide<80 || ((f==2 || f==3) && (green<500 || amber<4)) || ((f<2 || f==4) && amber!=0))$fatal(1,"missing overlay coverage");
  end
  $display("G1R OVERLAY PASS green supported/live edges; amber dashed short gaps; NONE no false box; circle marker; readable aligned diagnostic labels; blanking");$finish;
 end
endmodule
