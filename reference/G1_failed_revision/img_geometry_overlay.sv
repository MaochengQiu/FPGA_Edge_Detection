`timescale 1ns/1ps
module img_geometry_overlay #(parameter WIDTH=1920,HEIGHT=1080)(
 input clk,rst_n,input [3:0] ctl,input [1:0] shape,input [15:0] left,top,right,bottom,
 output paint,output [23:0] color);
 wire [15:0] x,y;wire unused_sof,unused_eol;
 img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(.clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),.x(x),.y(y),.sof(unused_sof),.eol(unused_eol));
 wire [15:0] cx=(left>>1)+(right>>1),cy=(top>>1)+(bottom>>1);
 wire box=shape>=2 && x>=left && x<=right && y>=top && y<=bottom && (x<=left+1 || x+1>=right || y<=top+1 || y+1>=bottom);
 wire crosshair=shape==1 && ((x>=cx-8 && x<=cx+8 && y==cy)||(y>=cy-8 && y<=cy+8 && x==cx));
 reg [47:0] label;
 always @*case(shape)1:label="CIRCLE";2:label="SQUARE";3:label="RECT  ";default:label="NONE  ";endcase
 wire [15:0] tx=x-16,ty=y-56;
 reg [7:0] letter;
 always @*case(tx/12)0:letter=label[47:40];1:letter=label[39:32];2:letter=label[31:24];3:letter=label[23:16];4:letter=label[15:8];5:letter=label[7:0];default:letter=32;endcase
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
 wire text_on=x>=16 && tx<72 && ty<14 && (tx%12)<10 && glyph[34-((ty>>1)*5+((tx%12)>>1))];
 assign paint=ctl[0] && (box || crosshair || text_on);
 assign color=shape!=0?24'h20ff40:24'hb0b0b0;
endmodule
