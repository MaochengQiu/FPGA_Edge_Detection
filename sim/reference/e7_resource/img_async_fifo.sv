`timescale 1ns/1ps
`default_nettype none
// Dual-clock FIFO with Gray-pointer CDC and registered prefetch output.
// DEPTH must be a power of two >=4. Payload stays stable under backpressure.
// Both resets must be asserted together; release is synchronized in each domain.
module img_async_fifo #(parameter integer BITS=128,DEPTH=1024)(
    input wire wr_clk,wr_rst_n,input wire wr_valid,output wire wr_ready,
    input wire [BITS-1:0] wr_data,
    input wire rd_clk,rd_rst_n,output reg rd_valid,input wire rd_ready,
    output reg [BITS-1:0] rd_data
);
    localparam integer AW=$clog2(DEPTH);
    (* ram_style="block" *) reg [BITS-1:0] mem[0:DEPTH-1];
    reg [AW:0] wb,wg,rb,rg;
    (* async_reg="true" *) reg [AW:0] rg1,rg2,wg1,wg2;
    reg full;
    wire push=wr_valid && wr_ready;
    wire [AW:0] wn=wb+push;
    wire [AW:0] wgn=(wn>>1)^wn;
    wire empty=(rg==wg2);
    wire fetch=rd_rst_n && (!rd_valid || rd_ready) && !empty;
    wire [AW:0] rn=rb+fetch;
    wire [AW:0] rgn=(rn>>1)^rn;
    assign wr_ready=wr_rst_n && ~full;
    always @(posedge wr_clk) if (push) mem[wb[AW-1:0]]<=wr_data;
    always @(posedge rd_clk) if (fetch) rd_data<=mem[rb[AW-1:0]];
    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin wb<=0;wg<=0;full<=0;rg1<=0;rg2<=0;end
        else begin
            rg1<=rg;rg2<=rg1;wb<=wn;wg<=wgn;
            full<=(wgn=={~rg2[AW:AW-1],rg2[AW-2:0]});
        end
    end
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin rb<=0;rg<=0;wg1<=0;wg2<=0;rd_valid<=0;end
        else begin
            wg1<=wg;wg2<=wg1;rb<=rn;rg<=rgn;
            if (!rd_valid || rd_ready) rd_valid<=!empty;
        end
    end
endmodule

`default_nettype wire
