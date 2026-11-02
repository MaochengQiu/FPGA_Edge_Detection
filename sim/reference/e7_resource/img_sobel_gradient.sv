`timescale 1ns/1ps
`default_nettype none
// Four stages: partial sums, signed gradients, absolute values, L1 magnitude.
// gx/gy are delayed to the same output token as magnitude. II=1.
module img_sobel_gradient(input wire clk,rst_n,input wire [71:0] pixels,
    output wire signed [10:0] gx,gy,output reg [10:0] magnitude);
    wire [7:0] p00=pixels[7:0],p01=pixels[15:8],p02=pixels[23:16];
    wire [7:0] p10=pixels[31:24],p12=pixels[47:40];
    wire [7:0] p20=pixels[55:48],p21=pixels[63:56],p22=pixels[71:64];
    reg [9:0] xp,xn,yp,yn;
    reg signed [10:0] xg,yg;
    reg [10:0] ax,ay;
    reg signed [10:0] xd,yd;
    reg signed [10:0] xo,yo;
    always @(posedge clk) begin
        if (!rst_n) begin
            xp<=0;xn<=0;yp<=0;yn<=0;xg<=0;yg<=0;ax<=0;ay<=0;
            xd<=0;yd<=0;xo<=0;yo<=0;magnitude<=0;
        end else begin
            xp<={2'd0,p02}+{1'd0,p12,1'b0}+{2'd0,p22};
            xn<={2'd0,p00}+{1'd0,p10,1'b0}+{2'd0,p20};
            yp<={2'd0,p20}+{1'd0,p21,1'b0}+{2'd0,p22};
            yn<={2'd0,p00}+{1'd0,p01,1'b0}+{2'd0,p02};
            xg<=$signed({1'b0,xp})-$signed({1'b0,xn});
            yg<=$signed({1'b0,yp})-$signed({1'b0,yn});
            ax<=xg[10]?$unsigned(-xg):$unsigned(xg);
            ay<=yg[10]?$unsigned(-yg):$unsigned(yg);
            xd<=xg;yd<=yg;xo<=xd;yo<=yd;
            magnitude<=ax+ay;
        end
    end
    assign gx=xo;assign gy=yo;
endmodule

`default_nettype wire
