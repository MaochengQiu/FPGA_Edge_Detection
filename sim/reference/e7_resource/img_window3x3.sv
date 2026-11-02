`timescale 1ns/1ps
`default_nettype none
// Two circular row RAMs; synchronous reads, then horizontal shifts.
// p00 is top-left; p22 is the arriving pixel. Center is (x-1,y-1).
// Window has two sampled stages; full-raster center delay is HTOTAL+3.
module img_window3x3 #(parameter integer BITS=8, WIDTH=1920, HEIGHT=1080)(
    input wire clk,rst_n,de,vs,
    input wire [BITS-1:0] pixel,
    output reg [9*BITS-1:0] window,
    output reg window_valid
);
    wire [15:0] x,y;wire unused_sof,unused_eol;
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(
        .clk(clk),.rst_n(rst_n),.de(de),.vs(vs),.x(x),.y(y),
        .sof(unused_sof),.eol(unused_eol));
    (* ram_style="block" *) reg [BITS-1:0] row0[0:WIDTH-1];
    (* ram_style="block" *) reg [BITS-1:0] row1[0:WIDTH-1];
    reg [BITS-1:0] q0,q1,current;
    reg q_de;reg [15:0] q_x,q_y;
    reg [BITS-1:0] t0,t1,m0,m1,b0,b1;
    wire [BITS-1:0] top=q_y[0]?q1:q0;
    wire [BITS-1:0] middle=q_y[0]?q0:q1;
    always @(posedge clk) if (rst_n && de && x<WIDTH) begin
        q0<=row0[x];q1<=row1[x];
        if (y[0]) row1[x]<=pixel;else row0[x]<=pixel;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            current<=0;q_de<=0;q_x<=0;q_y<=0;
            window<=0;window_valid<=0;
            t0<=0;t1<=0;m0<=0;m1<=0;b0<=0;b1<=0;
        end else begin
            current<=pixel;q_de<=de;q_x<=x;q_y<=y;
            window_valid<=q_de && q_x>=2 && q_x<WIDTH && q_y>=2 && q_y<HEIGHT;
            if (q_de) begin
                // At x=0, old columns are explicitly discarded.
                if (q_x==0) begin
                    t0<=0;t1<=top;m0<=0;m1<=middle;b0<=0;b1<=current;
                end else begin
                    t0<=t1;t1<=top;m0<=m1;m1<=middle;b0<=b1;b1<=current;
                end
                window<={current,b1,b0,middle,m1,m0,top,t1,t0};
            end
        end
    end
endmodule

`default_nettype wire
