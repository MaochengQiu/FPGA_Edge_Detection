`timescale 1ns/1ps
`default_nettype none
// Complete odd-even transposition comparator network: nine stages, II=1.
// 36 compare/exchange cells. Uses unsigned values; repeated values are legal.
module img_median9 #(parameter integer BITS=8)(
    input wire clk,rst_n,input wire [9*BITS-1:0] pixels,
    output wire [BITS-1:0] median
);
    wire [BITS-1:0] stage[0:9][0:8];
    genvar s,j;
    generate
        for (j=0;j<9;j=j+1) begin:g_in
            assign stage[0][j]=pixels[j*BITS+:BITS];
        end
        for (s=0;s<9;s=s+1) begin:g_stage
            for (j=0;j<9;j=j+1) begin:g_cell
                reg [BITS-1:0] q;
                if ((j%2)==(s%2) && j<8) begin:g_lo
                    always @(posedge clk) if (!rst_n) q<=0;
                        else q<=(stage[s][j]<stage[s][j+1])?stage[s][j]:stage[s][j+1];
                end else if (j>0 && ((j-1)%2)==(s%2)) begin:g_hi
                    always @(posedge clk) if (!rst_n) q<=0;
                        else q<=(stage[s][j]>stage[s][j-1])?stage[s][j]:stage[s][j-1];
                end else begin:g_copy
                    always @(posedge clk) if (!rst_n) q<=0;else q<=stage[s][j];
                end
                assign stage[s+1][j]=q;
            end
        end
    endgenerate
    assign median=stage[9][4];
endmodule

`default_nettype wire
