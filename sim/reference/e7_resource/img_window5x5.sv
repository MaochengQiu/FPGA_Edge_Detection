`timescale 1ns/1ps
`default_nettype none
// Four rotating row RAMs, read-before-write, then four horizontal taps.
// Output order: bit 0 is top-left, bit 24 bottom-right. Center delay 2*HTOTAL+4.
module img_window5x5 #(parameter integer BITS=5,WIDTH=1920,HEIGHT=1080)(
    input wire clk,rst_n,de,vs,input wire [BITS-1:0] pixel,
    output reg [25*BITS-1:0] window,output reg window_valid
);
    wire [15:0] x,y;wire us,ue;
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(.clk(clk),.rst_n(rst_n),.de(de),.vs(vs),
        .x(x),.y(y),.sof(us),.eol(ue));
    (* ram_style="block" *) reg [BITS-1:0] row0[0:WIDTH-1],row1[0:WIDTH-1],row2[0:WIDTH-1],row3[0:WIDTH-1];
    reg [BITS-1:0] q0,q1,q2,q3,current;
    reg [15:0] qx,qy;reg qde;
    reg [BITS-1:0] taps[0:19];
    wire [BITS-1:0] rows[0:4];
    assign rows[0]=(qy[1:0]==0)?q0:((qy[1:0]==1)?q1:((qy[1:0]==2)?q2:q3));
    assign rows[1]=(qy[1:0]==0)?q1:((qy[1:0]==1)?q2:((qy[1:0]==2)?q3:q0));
    assign rows[2]=(qy[1:0]==0)?q2:((qy[1:0]==1)?q3:((qy[1:0]==2)?q0:q1));
    assign rows[3]=(qy[1:0]==0)?q3:((qy[1:0]==1)?q0:((qy[1:0]==2)?q1:q2));
    assign rows[4]=current;
    always @(posedge clk)if(rst_n && de && x<WIDTH)begin
        q0<=row0[x];q1<=row1[x];q2<=row2[x];q3<=row3[x];
        case(y[1:0])0:row0[x]<=pixel;1:row1[x]<=pixel;2:row2[x]<=pixel;3:row3[x]<=pixel;endcase
    end
    integer r,c;
    always @(posedge clk)begin
        if(!rst_n)begin
            current<=0;qx<=0;qy<=0;qde<=0;window<=0;window_valid<=0;
            for(r=0;r<20;r=r+1)taps[r]<=0;
        end else begin
            current<=pixel;qx<=x;qy<=y;qde<=de;
            window_valid<=qde && qx>=4 && qx<WIDTH && qy>=4 && qy<HEIGHT;
            if(qde)for(r=0;r<5;r=r+1)begin
                if(qx==0)begin
                    for(c=0;c<3;c=c+1)taps[4*r+c]<=0;
                    taps[4*r+3]<=rows[r];
                end else begin
                    for(c=0;c<3;c=c+1)taps[4*r+c]<=taps[4*r+c+1];
                    taps[4*r+3]<=rows[r];
                end
                for(c=0;c<4;c=c+1)window[(r*5+c)*BITS+:BITS]<=taps[r*4+c];
                window[(r*5+4)*BITS+:BITS]<=rows[r];
            end
        end
    end
endmodule
`default_nettype wire
