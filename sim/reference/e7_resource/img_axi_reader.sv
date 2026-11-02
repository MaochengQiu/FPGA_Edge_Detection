`timescale 1ns/1ps
`default_nettype none
// One outstanding read burst. Emits a full black frame until a complete frame exists.
// Busy requests are coalesced in a one-entry pending latch, never silently lost.
// A new bank is selected only after the previous frame DMA has finished.
module img_axi_reader #(parameter integer DATA_BITS=128,ADDR_BITS=32,
    FRAME_BEATS=129600,MAX_BURST=128)(
    input wire clk,rst_n,request,input wire [31:0] frame_addr,input wire frame_valid,
    output wire fifo_valid,input wire fifo_ready,output wire [DATA_BITS:0] fifo_data,
    output wire [ADDR_BITS-1:0] araddr,output wire [7:0] arlen,
    output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
    input wire [DATA_BITS-1:0] rdata,input wire rvalid,rlast,input wire [1:0] rresp,
    output wire rready,output reg boundary,output reg [31:0] late_requests,read_errors
);
    localparam integer BYTES=DATA_BITS/8;
    localparam [2:0] IDLE=0,SELECT=1,LOAD=2,AR=3,R=4,ZERO=5;
    reg [2:0] state;reg [ADDR_BITS-1:0] addr;
    reg [31:0] remaining;reg [8:0] burst_beats,beat;
    reg request_pending;
    integer limit;
    wire rx=rvalid&&rready;
    always @* begin
        limit=(4096-(addr%4096))/BYTES;
        if (limit>MAX_BURST) limit=MAX_BURST;
        if (limit>remaining) limit=remaining;
    end
    assign araddr=addr;assign arlen=burst_beats[7:0]-8'd1;
    assign arsize=$clog2(BYTES);assign arburst=1;assign arvalid=state==AR;
    assign fifo_valid=(state==R && rvalid)||(state==ZERO);
    assign fifo_data={(remaining==FRAME_BEATS),(state==ZERO || rresp!=0)?{DATA_BITS{1'b0}}:rdata};
    assign rready=state==R && fifo_ready;
    always @(posedge clk) begin
        if (!rst_n) begin state<=IDLE;addr<=0;remaining<=0;burst_beats<=1;beat<=0;
            boundary<=0;late_requests<=0;read_errors<=0;request_pending<=0;end
        else begin
            boundary<=0;
            if(request && state!=IDLE) begin
                late_requests<=late_requests+1'b1;request_pending<=1;
            end
            case(state)
                IDLE:if (request || request_pending) begin
                    boundary<=1;state<=SELECT;request_pending<=0;
                end
                SELECT:state<=LOAD; // manager observes boundary on this edge
                LOAD:begin
                    addr<=frame_addr;remaining<=FRAME_BEATS;beat<=0;
                    burst_beats<=(FRAME_BEATS<MAX_BURST)?FRAME_BEATS:MAX_BURST;
                    state<=frame_valid?AR:ZERO;
                end
                ZERO:if (fifo_ready) begin
                    remaining<=remaining-1'b1;
                    if (remaining==1) state<=IDLE;
                end
                AR:if (arready) begin state<=R;beat<=0;end
                R:if (rx) begin
                    remaining<=remaining-1'b1;addr<=addr+BYTES;
                    if (rresp!=0 || rlast!=(beat==burst_beats-1'b1)) read_errors<=read_errors+1'b1;
                    if (beat==burst_beats-1'b1) begin
                        if (remaining==1) state<=IDLE;
                        else begin
                            // The next burst is calculated in SELECT-like state via AR preparation.
                            state<=3'd6;
                        end
                    end else beat<=beat+1'b1;
                end
                3'd6:begin burst_beats<=limit[8:0];state<=AR;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
