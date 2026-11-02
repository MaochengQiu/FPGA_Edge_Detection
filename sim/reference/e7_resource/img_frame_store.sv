`timescale 1ns/1ps
`default_nettype none
// RAW frame store. Camera words and output words are little-endian pixel groups.
// VS falling edge arms the next active frame; capture starts on the following DE.
// Accepts pulse-style VS or CSI generic level VS. FRAME_BYTES is an AXI-word multiple.
// External DDR controller/PHY is intentionally not implemented here.
module img_frame_store #(parameter integer I_BITS=32,O_BITS=16,AXI_BITS=128,
    ADDR_BITS=32,WIDTH=1920,HEIGHT=1080,FIFO_DEPTH=2048,MAX_BURST=128)(
    input wire cam_clk,cam_rst_n,input wire cam_vs,cam_de,input wire [I_BITS-1:0] cam_data,
    input wire axi_clk,axi_rst_n,input wire freeze,
    input wire out_clk,out_rst_n,frame_request,
    output wire [O_BITS-1:0] out_data,output wire out_valid,input wire out_ready,
    output wire out_sof,out_eol,
    output wire [ADDR_BITS-1:0] awaddr,output wire [7:0] awlen,
    output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
    output wire [AXI_BITS-1:0] wdata,output wire wvalid,wlast,input wire wready,
    input wire bvalid,input wire [1:0] bresp,output wire bready,
    output wire [ADDR_BITS-1:0] araddr,output wire [7:0] arlen,
    output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
    input wire [AXI_BITS-1:0] rdata,input wire rvalid,rlast,input wire [1:0] rresp,output wire rready,
    output wire [31:0] completed_frames,selected_frames,rejected_frames,late_requests,read_errors,
    output reg [31:0] capture_overflows,
    output reg capture_overflow_sticky
);
    localparam integer FRAME_BYTES=WIDTH*HEIGHT;
    localparam integer FRAME_BEATS=FRAME_BYTES/(AXI_BITS/8);
    localparam integer FRAME_WORDS=FRAME_BYTES/(I_BITS/8);
    localparam integer PACK=AXI_BITS/I_BITS;
    localparam integer UNPACK=AXI_BITS/O_BITS;
    localparam integer FRAME_STRIDE=((FRAME_BYTES+4095)/4096)*4096;
    localparam integer OWIDTH=WIDTH/(O_BITS/8);
    reg cam_vs_q,started,drop_frame;
    reg [31:0] camera_words;
    integer pack_index;
    reg [AXI_BITS-1:0] pack_data;
    reg [AXI_BITS+1:0] packed_data;reg packed_valid;
    wire packed_ready;
    wire in_valid,in_ready;wire [AXI_BITS+1:0] in_data;
    reg request_q,request_toggle;
    (* async_reg="true" *) reg [2:0] request_sync,freeze_sync;
    wire request_pulse=request_sync[2]^request_sync[1];
    wire [1:0] wr_bank,rd_bank;wire rd_frame_valid,wr_done,boundary;
    wire [31:0] wr_addr,rd_addr;
    wire read_push,read_ready;wire [AXI_BITS:0] read_payload;
    wire unpack_valid,unpack_ready;wire [AXI_BITS:0] unpack_payload;
    integer unpack_index;reg [15:0] ox;
    always @(posedge cam_clk) begin
        if (!cam_rst_n) begin
            cam_vs_q<=0;started<=0;drop_frame<=0;camera_words<=0;
            pack_index<=0;pack_data<=0;packed_data<=0;packed_valid<=0;capture_overflows<=0;
            capture_overflow_sticky<=0;
        end else begin
            cam_vs_q<=cam_vs;packed_valid<=0;
            if (packed_valid && !packed_ready) begin
                drop_frame<=1;capture_overflows<=capture_overflows+1'b1;
                capture_overflow_sticky<=1;
            end
            if (cam_vs_q && !cam_vs) begin
                started<=1;drop_frame<=0;camera_words<=0;pack_index<=0;
            end else if (cam_de && started && !drop_frame && camera_words<FRAME_WORDS) begin
                pack_data[pack_index*I_BITS+:I_BITS]<=cam_data;
                camera_words<=camera_words+1'b1;
                if (pack_index==PACK-1) begin
                    // Final input word is inserted explicitly, before the NBA update above.
                    packed_data<={(camera_words==FRAME_WORDS-1),(camera_words==PACK-1),
                                  cam_data,pack_data[AXI_BITS-I_BITS-1:0]};
                    packed_valid<=1;pack_index<=0;
                end else pack_index<=pack_index+1;
            end
        end
    end
    img_async_fifo #(.BITS(AXI_BITS+2),.DEPTH(FIFO_DEPTH)) capture_fifo(
        .wr_clk(cam_clk),.wr_rst_n(cam_rst_n),.wr_valid(packed_valid),.wr_ready(packed_ready),.wr_data(packed_data),
        .rd_clk(axi_clk),.rd_rst_n(axi_rst_n),.rd_valid(in_valid),.rd_ready(in_ready),.rd_data(in_data));
    always @(posedge out_clk) begin
        if(!out_rst_n) begin request_q<=0;request_toggle<=0;end
        else begin request_q<=frame_request;
            if(frame_request && !request_q) request_toggle<=~request_toggle;
        end
    end
    always @(posedge axi_clk) begin
        if(!axi_rst_n) begin request_sync<=0;freeze_sync<=0;end
        else begin
            request_sync<={request_sync[1:0],request_toggle};
            freeze_sync<={freeze_sync[1:0],freeze};
        end
    end
    img_frame_manager #(.FRAME_STRIDE(FRAME_STRIDE)) manager(
        .clk(axi_clk),.rst_n(axi_rst_n),.wr_done(wr_done),.rd_boundary(boundary),.freeze(freeze_sync[2]),
        .wr_bank(wr_bank),.rd_bank(rd_bank),.rd_valid(rd_frame_valid),.wr_addr(wr_addr),.rd_addr(rd_addr),
        .completed_frames(completed_frames),.selected_frames(selected_frames));
    img_axi_writer #(.DATA_BITS(AXI_BITS),.ADDR_BITS(ADDR_BITS),.FRAME_BEATS(FRAME_BEATS),.MAX_BURST(MAX_BURST)) writer(
        .clk(axi_clk),.rst_n(axi_rst_n),.frame_addr(wr_addr),
        .fifo_valid(in_valid),.fifo_ready(in_ready),.fifo_data(in_data),
        .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wvalid(wvalid),.wlast(wlast),.wready(wready),
        .bvalid(bvalid),.bresp(bresp),.bready(bready),.frame_done(wr_done),.rejected_frames(rejected_frames));
    img_axi_reader #(.DATA_BITS(AXI_BITS),.ADDR_BITS(ADDR_BITS),.FRAME_BEATS(FRAME_BEATS),.MAX_BURST(MAX_BURST)) reader(
        .clk(axi_clk),.rst_n(axi_rst_n),.request(request_pulse),.frame_addr(rd_addr),.frame_valid(rd_frame_valid),
        .fifo_valid(read_push),.fifo_ready(read_ready),.fifo_data(read_payload),
        .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
        .rdata(rdata),.rvalid(rvalid),.rlast(rlast),.rresp(rresp),.rready(rready),
        .boundary(boundary),.late_requests(late_requests),.read_errors(read_errors));
    img_async_fifo #(.BITS(AXI_BITS+1),.DEPTH(FIFO_DEPTH)) display_fifo(
        .wr_clk(axi_clk),.wr_rst_n(axi_rst_n),.wr_valid(read_push),.wr_ready(read_ready),.wr_data(read_payload),
        .rd_clk(out_clk),.rd_rst_n(out_rst_n),.rd_valid(unpack_valid),.rd_ready(unpack_ready),.rd_data(unpack_payload));
    assign out_valid=unpack_valid;
    assign out_data=unpack_payload[unpack_index*O_BITS+:O_BITS];
    assign out_sof=unpack_valid && unpack_payload[AXI_BITS] && unpack_index==0;
    assign out_eol=unpack_valid && ox==OWIDTH-1;
    assign unpack_ready=out_ready && unpack_index==UNPACK-1;
    always @(posedge out_clk) begin
        if(!out_rst_n) begin unpack_index<=0;ox<=0;end
        else if(out_valid && out_ready) begin
            if(unpack_index==UNPACK-1) unpack_index<=0;else unpack_index<=unpack_index+1;
            if(ox==OWIDTH-1) ox<=0;else ox<=ox+1'b1;
        end
    end
endmodule

`default_nettype wire
