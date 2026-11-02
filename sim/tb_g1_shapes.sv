`timescale 1ns/1ps
module tb_g1_shapes;
 reg clk=0,rst=0,e=0;always #5 clk=~clk;reg [3:0] ctl=0;
 wire [1:0] shape;wire [15:0] l,t,r,b;
 img_geometry #(.WIDTH(128),.HEIGHT(96),.S(2)) dut(.clk(clk),.rst_n(rst),.edge_pixel(e),.ctl(ctl),.shape(shape),.left(l),.top(t),.right(r),.bottom(b));
 integer f,x,y,dx,dy,d,q,expected=0,saved_shape,shift;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(f=0;f<14;f=f+1)begin
   @(negedge clk);ctl=4; e=0;@(posedge clk);#1;
   if(shape!==expected)$fatal(1,"frame%0d classification got%0d expected%0d bbox%0d %0d %0d %0d",f,shape,expected,l,t,r,b);
   if(f>=9 && shape==2 && (l!=44+(f-9)*2 || r!=75+(f-9)*2))$fatal(1,"moving bbox stale beyond prior frame");
   saved_shape=shape;
   @(negedge clk);ctl=0;
   shift=(f>=8)?(f-8)*2:0;
   for(y=0;y<96;y=y+1)for(x=0;x<160;x=x+1)begin
    @(negedge clk);ctl=(x<128)?1:0;e=0;
    dx=x-64;dy=y-48;d=dx*dx+dy*dy;
    case(f)
     0:e=d>=225 && d<=256;
     1:e=((x==44 || x==75) && y>=32 && y<=63)||((y==32||y==63)&&x>=44&&x<=75);
     2:e=((x==38 || x==85)&&y>=36&&y<=59)||((y==36||y==59)&&x>=38&&x<=85);
     3:begin q=(y-30)*20/35;e=y>=30&&y<=65&&(x==64-q || x==64+q || (y==65&&x>=44&&x<=84));end
     4:e=0;
     5:e=((x==44 || x==75)&&y>=32&&y<=63)||(y==63&&x>=44&&x<=75);
     6:e=d>=225&&d<=256 && !(x>64 && y<48);
     12:e=(x-58)*(x-58)+(y-44)*(y-44)>=121 && (x-58)*(x-58)+(y-44)*(y-44)<=144;
     13:e=0;
     7:e=x>=36&&x<90&&y>=28&&y<68;
     default:e=((x==44+shift||x==75+shift)&&y>=32&&y<=63)||((y==32||y==63)&&x>=44+shift&&x<=75+shift);
    endcase
    @(posedge clk);#1;if(shape!==saved_shape)$fatal(1,"result changed inside frame");
   end
   case(f)0:expected=1;1:expected=2;2:expected=3;3,4,5,6,7,13:expected=0;12:expected=1;default:expected=2;endcase
  end
  $display("G1 SHAPES PASS circle square rect triangle blank incomplete arc/dense and moving cards, frame commit");$finish;
 end
endmodule
