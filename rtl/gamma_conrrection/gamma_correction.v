// E8: fixed curve ROM replaces a continuously rewritten register/mux table.
// Same curve file, byte mapping, registered RGB latency and DE/HS/VS/reset.
module gamma_correction #(
    parameter DATA_WIDTH=10,
    parameter GAMMA_CURVE="2P2.mem"
)(
    input i_pclk,i_rstn,i_valid,i_hs,i_vs,
    input [DATA_WIDTH-1:0] i_red,i_green,i_blue,
    output reg [DATA_WIDTH-1:0] o_red,o_green,o_blue,
    output reg o_valid,o_hs,o_vs
);
    // Read-only after configuration: infer small synchronous ROM copies rather
    // than 1024 writable words with three large asynchronous read muxes.
    // Preserve the original source ROM's declared address order.
    (* ram_style="block" *) reg [9:0] curve[1023:0];
    initial $readmemh(GAMMA_CURVE,curve,0,1023);
    always @(posedge i_pclk)begin
        if(!i_rstn)begin
            o_red<=0;o_green<=0;o_blue<=0;o_valid<=0;o_hs<=0;o_vs<=0;
        end else begin
            o_valid<=i_valid;o_hs<=i_hs;o_vs<=i_vs;
            if(i_valid)begin
                if(DATA_WIDTH==10)begin
                    o_red<=curve[i_red];o_green<=curve[i_green];o_blue<=curve[i_blue];
                end else begin
                    o_red<=curve[{i_red,i_red[7:6]}][9:2];
                    o_green<=curve[{i_green,i_green[7:6]}][9:2];
                    o_blue<=curve[{i_blue,i_blue[7:6]}][9:2];
                end
            end else begin o_red<=0;o_green<=0;o_blue<=0;end
        end
    end
endmodule
