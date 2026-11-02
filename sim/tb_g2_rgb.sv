`timescale 1ns/1ps
module tb_g2_rgb;
 reg clk=0,rst=0,de=0,hs=0,vs=0;always #5 clk=~clk;
 reg [23:0] rgb=0;wire [23:0] out_rgb;wire od,oh,ov;
 img_pipeline #(.WIDTH(384),.HEIGHT(320),.HTOTAL(448),.NMS_ENABLE(1),.LINK_ENABLE(1),.QUALITY_FILTER_ENABLE(1),.G1_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),.cfg_preprocess(2'd2),.cfg_threshold(11'd50),.cfg_display(3'd7),.out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
integer curve_pixels=0;
 always @(posedge clk)if(rst && dut.shape==4 && dut.final_edge && dut.mark && dut.ink==24'h20ff40 && dut.g_geometry.overlay.y>=dut.gt && dut.g_geometry.overlay.y<=dut.gb)curve_pixels=curve_pixels+1;
 integer f,x,y,dx,dy,q,expected;reg [7:0] gray;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<8;f=f+1)begin
   for(y=0;y<340;y=y+1)for(x=0;x<448;x=x+1)begin
    @(negedge clk);de=y>=2&&y<322&&x<384;hs=x==388;vs=y==0;gray=200;dx=x-192;dy=y-2-160;
    case(f)
     0,1:if(dx*dx*784+dy*dy*3136<=2458624)gray=32;
     2:if(x>=136&&x<=247&&y-2>=104&&y-2<=215)gray=32;
     3:if(x>=112&&x<=271&&y-2>=112&&y-2<=207)gray=32;
     4:begin q=(y-2-104)/2;if(y-2>=104&&y-2<=216&&x>=192-q&&x<=192+q)gray=32;end
     6:if(x>=143&&x<=254&&y-2>=104&&y-2<=215)gray=32;
    endcase
    rgb=de?{gray,gray,gray}:0;
   end
   case(f)0:expected=0;1,2:expected=4;3:expected=2;4:expected=3;5,6:expected=0;7:expected=2;endcase
   if(dut.g_geometry.detect.shape!==expected)$fatal(1,"RGB frame%0d got%0d expected%0d",f,dut.g_geometry.detect.shape,expected);
  end
  if(curve_pixels<50)$fatal(1,"ellipse actual contour not colored %0d",curve_pixels);
  $display("G2 RGB PASS actual PRE2/Sobel/NMS/link circle square rect triangle blank/moving seven pixels, prior-frame result; circle >=12 pooled cells");$finish;
 end
endmodule
