`timescale 1ns/1ps
module tb_g1_overlay;
 reg clk=0,rst=0;always #5 clk=~clk;reg [3:0] ctl=0;reg [1:0] shape=3;
 wire paint;wire [23:0] color;
 img_geometry_overlay #(.WIDTH(128),.HEIGHT(96)) dut(.clk(clk),.rst_n(rst),.ctl(ctl),.shape(shape),.left(16'd40),.top(16'd32),.right(16'd75),.bottom(16'd63),.paint(paint),.color(color));
 integer f,x,y,painted,green;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<4;f=f+1)begin
   @(negedge clk);shape=f;ctl=4;@(negedge clk);ctl=0;painted=0;green=0;
   for(y=0;y<96;y=y+1)begin
    for(x=0;x<128;x=x+1)begin
     @(negedge clk);ctl=1;#1;
     if(paint)begin painted=painted+1;if(color==24'h20ff40)green=green+1;end
     if(f==0 && y<56 && paint)$fatal(1,"NONE drew false box");
     if(f==1 && x==57 && y==47 && !paint)$fatal(1,"circle center missing");
     if(f>=2 && x==40 && y==40 && !paint)$fatal(1,"box missing");
    end
    @(negedge clk);ctl=0;
   end
   if(painted<10 || (f>0 && green<10))$fatal(1,"label coverage f%0d painted%0d green%0d",f,painted,green);
  end
  $display("G1 OVERLAY PASS NONE no false box; CIRCLE green center; SQUARE/RECT box; reused HUD glyph labels");$finish;
 end
endmodule

