`timescale 1ns/1ps
`default_nettype none
// One pixel per active clock. Positive VS; frame begins after VS assertion.
// SOF is attached to the first active pixel, not to a sync pulse.
module img_coords #(parameter integer WIDTH=1920, HEIGHT=1080)(
    input wire clk,rst_n,de,vs,
    output wire [15:0] x,y,
    output wire sof,eol
);
    reg [15:0] xc,yc;
    reg de_q,vs_q;
    always @(posedge clk) begin
        if (!rst_n) begin xc<=0;yc<=0;de_q<=0;vs_q<=0;end
        else begin
            de_q<=de;vs_q<=vs;
            if (vs && !vs_q) begin xc<=0;yc<=0;end
            else begin
                if (de) begin
                    if (xc==WIDTH-1) xc<=0;else xc<=xc+1'b1;
                end else xc<=0;
                if (de_q && !de) begin
                    if (yc<HEIGHT) yc<=yc+1'b1;
                end
            end
        end
    end
    assign x=xc;assign y=yc;
    assign sof=de && xc==0 && yc==0;
    assign eol=de && xc==WIDTH-1;
endmodule

`default_nettype wire
