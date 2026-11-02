`timescale 1ns/1ps
`default_nettype none
// Modes: 0 RGB, 1 gray, 2 binary Sobel, 3 full-frame RGB/edge comparison,
// 4 edge overlay, 5 gradient magnitude. Exactly ONE clock of output latency.
//
// Mode 3 differs intentionally from a half-frame wipe: both halves show the
// SAME full-width camera field (horizontal decimation 2:1). A pair of line
// buffers is used because the right half of the source has not arrived yet
// when the left side of a display scanline is being emitted. Line y shows
// source line y-1; the first display line is blank. No frame buffer is added.
// WIDTH is even for the board's fixed 1920x1080 raster; odd widths are also
// supported for verification (the right viewport has one fewer column).
module img_composer #(parameter integer WIDTH=1920,HEIGHT=1080,
    parameter PAIR_EDGE=1'b1,G1_ENABLE=1'b0)(
    input wire clk,rst_n,input wire [3:0] ctl,
    input wire [23:0] rgb,input wire [7:0] gray,
    input wire geometry_mark,input wire [23:0] geometry_ink,
    input wire edge_pixel,input wire [10:0] magnitude,
    input wire [2:0] cfg_display,
    output wire [23:0] out_rgb,output reg [3:0] out_ctl
);
    localparam integer HALF=(WIDTH+1)/2;
    wire [15:0] x,y;wire unused_sof,unused_eol;
    reg [2:0] active_mode,mode_q;
    wire [2:0] mode=ctl[3]?cfg_display:active_mode;
    wire [7:0] mag8=(|magnitude[10:8])?8'hff:magnitude[7:0];
    reg [23:0] selected,normal_q;
    img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(
        .clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),.x(x),.y(y),
        .sof(unused_sof),.eol(unused_eol));

    // RGB keeps the original even-x decimation. A one-pixel edge on odd x
    // must also survive the half-width preview: OR the two edge samples.
    // PAIR_EDGE=0 restores the exact E1 even-x-only preview.
    reg [7:0] pair_rgb;reg pair_edge;
    wire pair_write=PAIR_EDGE?(x[0] || x==WIDTH-1):!x[0];
    wire [8:0] pair_sample=(PAIR_EDGE && x[0])?
        {pair_rgb,(pair_edge || edge_pixel)}:{gray,edge_pixel};
    // 25 bits = unchanged RGB888 sample plus one binary preview edge.
    // At any time one RAM is written with the current row, while the other
    // RAM is read to display the preceding row twice (left RGB, right edge).
    (* ram_style="block" *) reg [8:0] row_even[0:HALF-1];
    (* ram_style="block" *) reg [8:0] row_odd[0:HALF-1];
    reg [8:0] even_read,odd_read;
    reg read_even_q,right_q,split_valid_q;
    wire [15:0] read_addr=(x<HALF)?x:(x-HALF);
    wire [8:0] sample_q=read_even_q?even_read:odd_read;
    wire [23:0] split_color=right_q?
        (sample_q[0]?24'hffffff:24'h000000):{3{sample_q[8:1]}};

    always @* begin
        case(mode)
            0:selected=rgb;
            1:selected={gray,gray,gray};
            2:selected=edge_pixel?24'hffffff:24'h000000;
            3:selected=rgb;  // replaced by the line-buffered mirrored view
            4:selected=edge_pixel?24'hff3020:rgb;
            5:selected={mag8,mag8,mag8};
            // E5 A/B probe: EXACT same selected_edge, only RGB codewords differ.
            // Slightly tinted near-white / near-black; no new edge decision.
            7:selected=G1_ENABLE?(geometry_mark?geometry_ink:rgb):(edge_pixel?24'he0f0ff:24'h000103);
            default:selected=rgb;
        endcase
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            active_mode<=3;mode_q<=3;normal_q<=0;out_ctl<=0;
            even_read<=0;odd_read<=0;
            pair_rgb<=0;pair_edge<=0;
            read_even_q<=0;right_q<=0;split_valid_q<=0;
        end else begin
            if (ctl[3]) active_mode<=cfg_display;
            mode_q<=mode;
            normal_q<=ctl[0]?selected:24'd0;
            out_ctl<=ctl;
            read_even_q<=y[0];
            right_q<=x>=HALF;
            split_valid_q<=ctl[0] && x<WIDTH && y>0 && y<HEIGHT;
            if (ctl[0] && x<WIDTH && y<HEIGHT) begin
                if (!x[0]) begin pair_rgb<=gray;pair_edge<=edge_pixel;end
                if (y[0]) begin
                    // Odd source row: fill odd RAM, read preceding even row.
                    if (pair_write) row_odd[x>>1]<=pair_sample;
                    even_read<=row_even[read_addr];
                end else begin
                    // Even source row: fill even RAM, read preceding odd row.
                    if (pair_write) row_even[x>>1]<=pair_sample;
                    odd_read<=row_odd[read_addr];
                end
            end
        end
    end
    assign out_rgb=(mode_q==3)?
        (split_valid_q?split_color:24'h000000):normal_q;
endmodule

`default_nettype wire
