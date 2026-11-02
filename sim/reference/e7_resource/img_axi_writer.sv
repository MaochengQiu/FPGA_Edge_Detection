`timescale 1ns/1ps
`default_nettype none
// AXI4 frame writer. AW/W bursts remain ordered; B responses are pipelined.
// Publish only after ALL responses for the frame have returned successfully.
// Tag layout: {eof,sof,payload}. Burst limits obey 4KiB boundaries.
// A missing/dropped input frame is padded to finish announced AXI transactions,
// then rejected; next SOF is preserved for recovery. No incomplete publication.
module img_axi_writer #(parameter integer DATA_BITS=128,ADDR_BITS=32,
    FRAME_BEATS=129600,MAX_BURST=128,MAX_OUTSTANDING=4)(
    input wire clk,rst_n,input wire [31:0] frame_addr,
    input wire fifo_valid,output wire fifo_ready,input wire [DATA_BITS+1:0] fifo_data,
    output wire [ADDR_BITS-1:0] awaddr,output wire [7:0] awlen,
    output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
    output wire [DATA_BITS-1:0] wdata,output wire wvalid,wlast,input wire wready,
    input wire bvalid,input wire [1:0] bresp,output wire bready,
    output reg frame_done,output reg [31:0] rejected_frames
);
    localparam integer BYTES=DATA_BITS/8;
    localparam [2:0] IDLE=0,AW=1,W=2,PREP=3,DRAIN=4,HOLD=5;
    localparam integer BCW=$clog2(MAX_OUTSTANDING+1);
    localparam [8:0] FIRST_BURST=(FRAME_BEATS<MAX_BURST)?FRAME_BEATS:MAX_BURST;
    reg [2:0] state;reg [ADDR_BITS-1:0] addr;
    reg [31:0] remaining;reg [8:0] burst_beats,beat;
    reg bad,padding;
    reg [BCW-1:0] pending_b;
    integer limit;
    wire tag_sof=fifo_data[DATA_BITS];wire tag_eof=fifo_data[DATA_BITS+1];
    wire unexpected_sof=remaining!=FRAME_BEATS && fifo_valid && tag_sof;
    wire pad=padding || unexpected_sof;
    wire wx=wvalid&&wready;
    wire ax=awvalid&&awready;
    wire bx=bvalid&&bready;
    always @* begin
        limit=(4096-(addr%4096))/BYTES;
        if (limit>MAX_BURST) limit=MAX_BURST;
        if (limit>remaining) limit=remaining;
    end
    assign awaddr=addr;assign awlen=burst_beats[7:0]-8'd1;
    assign awsize=$clog2(BYTES);assign awburst=2'b01;
    assign awvalid=state==AW && pending_b<MAX_OUTSTANDING;
    assign wvalid=state==W && (fifo_valid || pad);
    assign wdata=pad?{DATA_BITS{1'b0}}:fifo_data[DATA_BITS-1:0];
    assign wlast=beat==burst_beats-1'b1;
    assign fifo_ready=(state==IDLE && fifo_valid && !tag_sof) || (wx && !pad);
    assign bready=rst_n;
    always @(posedge clk) begin
        if (!rst_n) begin state<=IDLE;addr<=0;remaining<=0;burst_beats<=1;beat<=0;
            bad<=0;padding<=0;pending_b<=0;frame_done<=0;rejected_frames<=0;end
        else begin
            frame_done<=0;
            case ({ax,bx})
                2'b10:pending_b<=pending_b+1'b1;
                2'b01:if(pending_b!=0)pending_b<=pending_b-1'b1;
                default:begin end
            endcase
            case(state)
                IDLE:if (fifo_valid && tag_sof) begin
                    addr<=frame_addr;remaining<=FRAME_BEATS;bad<=0;padding<=0;state<=AW;
                    // Bank addresses are 4KiB aligned; first burst can be set directly.
                    burst_beats<=FIRST_BURST;
                    beat<=0;
                end
                AW:if (ax) begin state<=W;beat<=0;end
                W:if (wx) begin
                    if (pad) begin bad<=1;padding<=1;end
                    else if (tag_eof!=(remaining==1)) begin
                        bad<=1;if(tag_eof) padding<=1;
                    end
                    remaining<=remaining-1'b1;addr<=addr+BYTES;
                    if (wlast) state<=(remaining==1)?DRAIN:PREP;
                    else beat<=beat+1'b1;
                end
                PREP:begin burst_beats<=limit[8:0];state<=AW;end
                DRAIN:if (pending_b==0) begin
                    if (!bad) frame_done<=1;
                    else rejected_frames<=rejected_frames+1'b1;
                    state<=HOLD;
                end
                HOLD:state<=IDLE; // allow manager to advance the write bank
                default:state<=IDLE;
            endcase
            if(bx && bresp!=0) bad<=1;
        end
    end
endmodule

`default_nettype wire
