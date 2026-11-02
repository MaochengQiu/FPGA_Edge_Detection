`timescale 1ns/1ps
`default_nettype none
// Asynchronous assertion, synchronous release. One instance per clock domain.
module img_reset_sync(input wire clk, input wire arst_n, output wire rst_n);
    (* async_reg = "true" *) reg [2:0] sync_q;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) sync_q <= 3'b000;
        else sync_q <= {sync_q[1:0],1'b1};
    assign rst_n = sync_q[2];
endmodule

`default_nettype wire
