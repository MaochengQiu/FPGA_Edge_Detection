`timescale 1ns/1ps
`default_nettype none
// CYCLES counts sampled-clock stages: CYCLES=1 is one register.
// The long path uses read-before-write circular RAM. RAM is never reset.
module img_delay #(parameter integer BITS=8, CYCLES=1)(
    input wire clk, rst_n, input wire [BITS-1:0] din,
    output wire [BITS-1:0] dout
);
    generate
        if (CYCLES==0) begin:g_wire
            assign dout=din;
        end else if (CYCLES==1) begin:g_reg
            reg [BITS-1:0] q;
            always @(posedge clk) if (!rst_n) q<=0; else q<=din;
            assign dout=q;
        end else begin:g_ram
            localparam integer DEPTH=CYCLES-1;
            localparam integer AW=(DEPTH<2)?1:$clog2(DEPTH);
            localparam integer CW=$clog2(CYCLES+1);
            (* ram_style="block" *) reg [BITS-1:0] mem[0:DEPTH-1];
            reg [AW-1:0] ptr;
            reg [CW-1:0] fill;
            reg [BITS-1:0] q;
            always @(posedge clk) if (rst_n) begin
                q<=mem[ptr];
                mem[ptr]<=din;
            end
            always @(posedge clk) begin
                if (!rst_n) begin ptr<=0;fill<=0;end
                else begin
                    if (ptr==DEPTH-1) ptr<=0;else ptr<=ptr+1'b1;
                    if (fill<CYCLES) fill<=fill+1'b1;
                end
            end
            assign dout=(fill==CYCLES)?q:{BITS{1'b0}};
        end
    endgenerate
endmodule

`default_nettype wire
