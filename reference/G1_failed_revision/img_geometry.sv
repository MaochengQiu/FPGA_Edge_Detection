`timescale 1ns/1ps
// Single complete target in central ROI. SxS OR pooling retains every edge.
// Read/compute FSM runs only after ROI; completed result commits at VS.
module img_geometry #(parameter WIDTH=1920,HEIGHT=1080,S=8)(
 input clk,rst_n,edge_pixel,input [3:0] ctl,
 output reg [1:0] shape,output reg [15:0] left,top,right,bottom);
 localparam RX=WIDTH/4,RY=HEIGHT/4,RW=WIDTH/2,RH=HEIGHT/2;
 localparam CW=(RW+S-1)/S,CH=(RH+S-1)/S,AW=$clog2(CW*CH);
 wire [15:0] x,y;wire us,ue;
 img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(.clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),.x(x),.y(y),.sof(us),.eol(ue));
 wire roi=ctl[0] && x>=RX && x<RX+RW && y>=RY && y<RY+RH;
 wire [15:0] ux=x-RX,uy=y-RY;
 wire [7:0] cx=ux/S,cy=uy/S;
 reg [CW-1:0] row_or;
 reg horizontal;
 wire partial=(ux%S==0)?edge_pixel:(horizontal|edge_pixel);
 wire pooled=(uy%S==0)?partial:(partial|row_or[cx]);
 (* ram_style="block" *) reg bitmap[0:CW*CH-1];
 reg have,vsq,ready;
 reg [7:0] xmin,xmax,ymin,ymax,sx,sy,px,py;
 reg [AW-1:0] address;
 reg cell_q;
 reg [3:0] state;
 reg [8:0] centerx,centery,w,h,radius;
 reg signed [9:0] dx,dy;
 reg [20:0] distance2,radius2;
 wire radial=distance2>radius2?(distance2-radius2<=(radius2>>2)+(radius<<2)):(radius2-distance2<=(radius2>>2)+(radius<<2));
 reg [CW-1:0] top_mask,bottom_mask,ctop,cbottom;
 reg [CH-1:0] left_mask,right_mask,cleft,cright;
 reg [3:0] corners;
 reg [7:0] sectors;
 reg [15:0] count,band_count,inliers;
 reg [8:0] checkindex;
 reg rect_bad,circle_bad;
 reg [1:0] pending;
 reg [15:0] pl,pt,pr,pb;
 wire lband=px<=xmin+1,rband=px+1>=xmax,tband=py<=ymin+1,bband=py+1>=ymax;
 wire [9:0] ax=dx<0?-dx:dx,ay=dy<0?-dy:dy;
 wire [2:0] sector={dx<0,dy<0,ax>ay};
 always @(posedge clk)begin
  if(!rst_n)begin
   shape<=0;left<=0;top<=0;right<=0;bottom<=0;vsq<=0;ready<=0;pending<=0;
   state<=0;have<=0;horizontal<=0;row_or<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;
   sx<=0;sy<=0;px<=0;py<=0;address<=0;cell_q<=0;centerx<=0;centery<=0;w<=0;h<=0;radius<=0;
   dx<=0;dy<=0;distance2<=0;radius2<=0;top_mask<=0;bottom_mask<=0;left_mask<=0;right_mask<=0;
   ctop<=0;cbottom<=0;cleft<=0;cright<=0;corners<=0;sectors<=0;count<=0;band_count<=0;inliers<=0;
   checkindex<=0;rect_bad<=0;circle_bad<=0;pl<=0;pt<=0;pr<=0;pb<=0;
  end else begin
   vsq<=ctl[2];
   if(ctl[2] && !vsq)begin
    shape<=ready?pending:0;left<=pl;top<=pt;right<=pr;bottom<=pb;
    ready<=0;have<=0;state<=0;horizontal<=0;
   end else begin
    if(roi && state==0)begin
     horizontal<=partial;
     if(ux%S==S-1 || ux==RW-1)begin
      row_or[cx]<=pooled;
      if(uy%S==S-1 || uy==RH-1)begin
       bitmap[cy*CW+cx]<=pooled;
       if(pooled)begin
        have<=1;
        if(!have || cx<xmin)xmin<=cx;
        if(!have || cx>xmax)xmax<=cx;
        if(!have || cy<ymin)ymin<=cy;
        if(!have || cy>ymax)ymax<=cy;
       end
      end
     end
     if(ux==RW-1 && uy==RH-1)state<=1;
    end
    case(state)
     1:begin
      w<={1'b0,xmax}-{1'b0,xmin}+1;h<={1'b0,ymax}-{1'b0,ymin}+1;
      centerx<={1'b0,xmin}+xmax;centery<={1'b0,ymin}+ymax;
      radius<=(({1'b0,xmax}-xmin)+({1'b0,ymax}-ymin))>>1;
      address<=0;sx<=0;sy<=0;count<=0;band_count<=0;inliers<=0;
      top_mask<=0;bottom_mask<=0;left_mask<=0;right_mask<=0;ctop<=0;cbottom<=0;cleft<=0;cright<=0;corners<=0;sectors<=0;
      state<=2;
     end
     2:begin radius2<=radius*radius;state<=3;end
     3:begin cell_q<=bitmap[address];px<=sx;py<=sy;state<=4;end
     4:begin dx<=$signed({1'b0,px,1'b0})-$signed({1'b0,centerx});dy<=$signed({1'b0,py,1'b0})-$signed({1'b0,centery});state<=5;end
     5:begin distance2<=dx*dx+dy*dy;state<=6;end
     6:begin
      if(cell_q)begin
       count<=count+1'b1;
       if(lband || rband || tband || bband)band_count<=band_count+1'b1;
       if(lband)left_mask[py]<=1;if(rband)right_mask[py]<=1;
       if(tband)top_mask[px]<=1;if(bband)bottom_mask[px]<=1;
       if(lband && tband)corners[0]<=1;if(rband && tband)corners[1]<=1;
       if(lband && bband)corners[2]<=1;if(rband && bband)corners[3]<=1;
       if(radial)begin
        inliers<=inliers+1'b1;sectors[sector]<=1;
        if(dx<=0)cleft[py]<=1;if(dx>=0)cright[py]<=1;
        if(dy<=0)ctop[px]<=1;if(dy>=0)cbottom[px]<=1;
       end
      end
      if(address==CW*CH-1)begin checkindex<=0;rect_bad<=0;circle_bad<=0;state<=7;end
      else begin address<=address+1'b1;if(sx==CW-1)begin sx<=0;sy<=sy+1'b1;end else sx<=sx+1'b1;state<=3;end
     end
     7:begin
      if(checkindex>=ymin && checkindex<=ymax && checkindex<CH)
       if(!left_mask[checkindex] || !right_mask[checkindex])rect_bad<=1;
      if(checkindex>=xmin && checkindex<=xmax && checkindex<CW)
       if(!top_mask[checkindex] || !bottom_mask[checkindex])rect_bad<=1;
      if(checkindex>ymin+1 && checkindex+1<ymax && checkindex<CH)
       if(!cleft[checkindex] || !cright[checkindex])circle_bad<=1;
      if(checkindex>xmin+1 && checkindex+1<xmax && checkindex<CW)
       if(!ctop[checkindex] || !cbottom[checkindex])circle_bad<=1;
      if(checkindex>=CW && checkindex>=CH)state<=8;else checkindex<=checkindex+1'b1;
     end
     8:begin
      pending<=0;
      if(have && xmin>0 && ymin>0 && xmax<CW-1 && ymax<CH-1 && w>=8 && h>=8 && count>=16)begin
       if(!rect_bad && (&corners) && band_count*8>=count*7)
        pending<=((w>h?w-h:h-w)<=(w>h?w:h)/8)?2:3;
       else if(!circle_bad && (&sectors) && inliers*10>=count*9 && w*5<=h*6 && h*5<=w*6)pending<=1;
      end
      pl<=RX+xmin*S;pt<=RY+ymin*S;pr<=RX+(xmax+1)*S-1;pb<=RY+(ymax+1)*S-1;
      ready<=1;state<=9;
     end
    endcase
   end
  end
 end
endmodule
