`timescale 1ps/1ps
`default_nettype none
// Video-only DVI/TMDS transport. Derived from supplied board demo dvi_encoder.v.
// Existing external 10:1 serializer, clock word, lane order and inversion stay unchanged.
// Each RGB/control input has identical three-register encoding latency.
module edge_dvi_encoder(
    input wire pixelclk, rst_p,
    input wire [7:0] i_bdata, i_gdata, i_rdata,
    input wire i_hs, i_vs, i_de,
    output wire [9:0] tmds_data0, tmds_data1, tmds_data2, tmds_clk
);
    edge_dvi_encode blue(.clkin(pixelclk),.rstin(rst_p),.din(i_bdata),
        .c0(i_hs),.c1(i_vs),.de(i_de),.dout(tmds_data0));
    edge_dvi_encode green(.clkin(pixelclk),.rstin(rst_p),.din(i_gdata),
        .c0(1'b0),.c1(1'b0),.de(i_de),.dout(tmds_data1));
    edge_dvi_encode red(.clkin(pixelclk),.rstin(rst_p),.din(i_rdata),
        .c0(1'b0),.c1(1'b0),.de(i_de),.dout(tmds_data2));
    assign tmds_clk=10'b1111100000;
endmodule
`default_nettype wire
