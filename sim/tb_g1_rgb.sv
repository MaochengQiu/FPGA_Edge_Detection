`timescale 1ns/1ps
module tb_g1_rgb;
 reg clk=0,rst=0,de=0,hs=0,vs=0;always #5 clk=~clk;
 reg [23:0] rgb=0;wire [23:0] out_rgb;wire od,oh,ov;
 img_pipeline #(.WIDTH(256),.HEIGHT(192),.HTOTAL(288),.NMS_ENABLE(1),.LINK_ENABLE(1),.QUALITY_FILTER_ENABLE(1),.G1_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),.cfg_preprocess(2'd2),.cfg_threshold(11'd50),.cfg_display(3'd7),.out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
 integer f,x,y,dx,dy,q,expected;reg [7:0] gray;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<7;f=f+1)begin
   for(y=0;y<212;y=y+1)for(x=0;x<288;x=x+1)begin
    @(negedge clk);de=y>=2&&y<194&&x<256;hs=x==260;vs=y==0;gray=200;dx=x-128;dy=y-2-96;
    case(f)
     0:if(dx*dx+dy*dy<=1156)gray=32;
     1:if(x>=90&&x<=161&&y-2>=60&&y-2<=131)gray=32;
     2:if(x>=80&&x<=175&&y-2>=64&&y-2<=127)gray=32;
     3:begin q=(y-2-60)/2;if(y-2>=60&&y-2<=132&&x>=128-q&&x<=128+q)gray=32;end
     5:if(x>=98&&x<=169&&y-2>=60&&y-2<=131)gray=32;
    endcase
    rgb=de?{gray,gray,gray}:0;
   end
   case(f)0:expected=0;1:expected=1;2:expected=2;3:expected=3;4,5:expected=0;6:expected=2;endcase
   if(dut.g_geometry.detect.shape!==expected)$fatal(1,"RGB frame%0d got%0d expected%0d",f,dut.g_geometry.detect.shape,expected);
  end
  $display("G1 RGB PASS actual PRE2/Sobel/NMS/link circle square rect triangle blank/moving, prior-frame result");$finish;
 end
endmodule
