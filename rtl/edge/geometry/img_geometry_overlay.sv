`timescale 1ns/1ps
`default_nettype none
// Green = supported contour model; amber dashes = locally missing support.
// Support masks and bbox are the same completed previous-frame snapshot.
module img_geometry_overlay #(parameter WIDTH=1920,HEIGHT=1080,S=4)(
 input wire clk,rst_n,input wire [3:0] ctl,input wire edge_pixel,
 input wire [2:0] shape,input wire [15:0] left,top,right,bottom,
 input wire [((HEIGHT/2+S-1)/S)*8-1:0] row_lo,row_hi,
 input wire [3:0] debug_reason,input wire [15:0] debug_cells,debug_count,
 input wire [31:0] debug_sides,input wire [7:0] debug_radial,
 input wire [((WIDTH/2+S-1)/S)-1:0] support_top,support_bottom,
 input wire [((HEIGHT/2+S-1)/S)-1:0] support_left,support_right,
 output wire paint,output wire [23:0] color);
 localparam RX=WIDTH/4,RY=HEIGHT/4,RW=WIDTH/2,RH=HEIGHT/2;
 localparam CW=(RW+S-1)/S,CH=(RH+S-1)/S;
 wire [15:0] x,y;wire unused_sof,unused_eol;
 img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(.clk(clk),.rst_n(rst_n),
  .de(ctl[0]),.vs(ctl[2]),.x(x),.y(y),.sof(unused_sof),.eol(unused_eol));
 wire [15:0] cx=(left>>1)+(right>>1),cy=(top>>1)+(bottom>>1);
 wire inside_box=x>=left && x<=right && y>=top && y<=bottom;
 wire on_top=inside_box && y<=top+1,on_bottom=inside_box && y+1>=bottom;
 wire on_left=inside_box && x<=left+1,on_right=inside_box && x+1>=right;
 wire box=(shape==2 || shape==3) && (on_top || on_bottom || on_left || on_right);
 wire [15:0] gx=(x-RX)/S,gy=(y-RY)/S;
 wire supported=(gx<CW && ((on_top && support_top[gx]) || (on_bottom && support_bottom[gx]))) ||
  (gy<CH && ((on_left && support_left[gy]) || (on_right && support_right[gy])));
 wire [15:0] rect_band=(right-left<bottom-top?(right-left+1):(bottom-top+1))/8;
 wire [15:0] rb=rect_band<8?16'd8:(rect_band>24?16'd24:rect_band);
 wire rect_recolor=(shape==2 || shape==3) && edge_pixel && inside_box &&
  (x<left+rb || x+rb>right || y<top+rb || y+rb>bottom);
 wire [7:0] curve_l=row_lo[gy*8+:8],curve_r=row_hi[gy*8+:8];
 wire [15:0] curve_band=(y<top+(bottom-top)/8 || y+(bottom-top)/8>bottom)?16'd6:16'd2;
 wire curve= (shape==1 || shape==4) && inside_box && gy<CH && curve_l<=curve_r &&
  ((gx+curve_band>=curve_l && gx<=curve_l+curve_band) || (gx+curve_band>=curve_r && gx<=curve_r+curve_band) || y<top+S || y+S>bottom);
 wire recolor=rect_recolor || (curve && edge_pixel);
 wire crosshair=(shape==1 || shape==4) && ((x+8>=cx && x<=cx+8 && y==cy)||(y+8>=cy && y<=cy+8 && x==cx));
 // Four short neutral corner guides, never a recognized target box.
 wire in_roi=x>=RX && x<RX+RW && y>=RY && y<RY+RH;
 wire guide=in_roi && (((x==RX || x==RX+RW-1) && (y<RY+12 || y>=RY+RH-12)) ||
  ((y==RY || y==RY+RH-1) && (x<RX+12 || x>=RX+RW-12)));
 reg [55:0] label;reg [63:0] status;
 always @*begin
  case(shape)1:label="CIRCLE ";2:label="SQUARE ";3:label="RECT   ";4:label="ELLIPSE";default:label="NONE   ";endcase
  case(debug_reason)
   0:status="OK      ";1:status="WARMUP  ";2:status="NOEDGE  ";3:status="SIZE    ";
   4:status="SHAPE   ";5:status="MULTI   ";6:status="LIMIT   ";7:status="TIMEOUT ";
   8:status="GAP     ";9:status="CLUTTER ";default:status="UNKNOWN ";
  endcase
 end
 function [7:0] hx(input [3:0] n);begin hx=n<10?8'd48+n:8'd55+n;end endfunction
 function [15:0] h2(input [7:0] n);begin h2={hx(n[7:4]),hx(n[3:0])};end endfunction
 function [31:0] h4(input [15:0] n);begin h4={h2(n[15:8]),h2(n[7:0])};end endfunction
 wire [15:0] pixel_w=shape!=0?right-left+1:0,pixel_h=shape!=0?bottom-top+1:0;
 wire [15:0] tx=x-16,ty=y-56;
 wire [1:0] text_row=ty<18?0:(ty<36?1:(ty<54?2:3));
 wire [15:0] text_y=ty<18?ty:(ty<36?ty-18:(ty<54?ty-36:ty-54));
 reg [255:0] line_text;
 always @*begin
  case(text_row)
   0:line_text={"G2  ",label," ",status,"            "};
   1:line_text={"E:",h4(debug_cells)," N:",h4(debug_count)," A:",h2(debug_radial),"              "};
   2:line_text={"T:",h2(debug_sides[31:24])," B:",h2(debug_sides[23:16])," L:",h2(debug_sides[15:8])," R:",h2(debug_sides[7:0]),"             "};
   3:line_text={"W:",h4(pixel_w)," H:",h4(pixel_h)," PX HEX            "};
   default:line_text=0;
  endcase
 end
 reg [7:0] letter;
 always @*begin
  letter=32;
  if(tx<512)letter=line_text[255-tx[8:4]*8-:8];
 end
    function [34:0] font5(input [7:0] c);
        begin case(c)
            8'h20:font5=35'h000000000;
            8'h41:font5=35'h3a31fc631;
            8'h42:font5=35'h7a31f463e;
            8'h43:font5=35'h3e108420f;
            8'h44:font5=35'h7a318c63e;
            8'h45:font5=35'h7e10f421f;
            8'h46:font5=35'h7e10f4210;
            8'h47:font5=35'h3e10bc62f;
            8'h48:font5=35'h4631fc631;
            8'h49:font5=35'h7c842109f;
            8'h4a:font5=35'h1c4214a4c;
            8'h4b:font5=35'h4654c5251;
            8'h4c:font5=35'h42108421f;
            8'h4d:font5=35'h4775ac631;
            8'h4e:font5=35'h47359c631;
            8'h4f:font5=35'h3a318c62e;
            8'h50:font5=35'h7a31f4210;
            8'h51:font5=35'h3a318d64d;
            8'h52:font5=35'h7a31f5251;
            8'h53:font5=35'h3e107043e;
            8'h54:font5=35'h7c8421084;
            8'h55:font5=35'h46318c62e;
            8'h56:font5=35'h46318c544;
            8'h57:font5=35'h4631ad6aa;
            8'h58:font5=35'h462a22a31;
            8'h59:font5=35'h462a21084;
            8'h5a:font5=35'h7c222221f;
            8'h30:font5=35'h3a75ae62e;
            8'h31:font5=35'h11842108e;
            8'h32:font5=35'h3a211111f;
            8'h33:font5=35'h78217043e;
            8'h34:font5=35'h08ca97c42;
            8'h35:font5=35'h7e10f043e;
            8'h36:font5=35'h3a10f462e;
            8'h37:font5=35'h7c2222108;
            8'h38:font5=35'h3a317462e;
            8'h39:font5=35'h3a317842e;
            8'h3a:font5=35'h008401080;
            8'h2e:font5=35'h0000000c6;
            8'h2f:font5=35'h042222210;
            8'h2b:font5=35'h0084f9080;
            8'h2d:font5=35'h0000f8000;
            8'h3d:font5=35'h001f07c00;
            8'h28:font5=35'h088842082;
            8'h29:font5=35'h208210888;
            default:font5=0;
        endcase end
    endfunction

 wire [34:0] glyph=font5(letter);
 wire text_on=x>=16 && tx<512 && ty<72 && text_y<14 && tx[3:0]<10 &&
  glyph[34-((text_y>>1)*5+(tx[3:0]>>1))];
 wire predicted=box && !supported && x[2]==y[2];
 assign paint=ctl[0] && (text_on || guide || recolor || crosshair || (box && supported) || predicted);
 assign color=text_on?(shape!=0?24'h20ff40:24'hb0b0b0):
  guide?24'h606060:(recolor || crosshair || (box && supported))?24'h20ff40:24'hffb020;
endmodule
`default_nettype wire
