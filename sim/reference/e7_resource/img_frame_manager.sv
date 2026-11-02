`timescale 1ns/1ps
`default_nettype none
// Triple-buffer latest-frame policy. Writer/display/latest-completed never alias.
// wr_done means all W beats AND successful B responses completed, not an AW event.
// rd_boundary means previous frame DMA and display consumption are finished.
// Freeze protects the display bank; capture continues using the other two banks.
module img_frame_manager #(parameter integer FRAME_STRIDE=2076672)(
    input wire clk,rst_n,wr_done,rd_boundary,freeze,
    output reg [1:0] wr_bank,rd_bank,
    output reg rd_valid,
    output wire [31:0] wr_addr,rd_addr,
    output reg [31:0] completed_frames,selected_frames
);
    reg [1:0] ready_bank;reg ready_valid;
    reg [1:0] nw,nr,nready;reg nvalid,nready_valid;
    integer i;
    always @* begin
        nw=wr_bank;nr=rd_bank;nready=ready_bank;nvalid=rd_valid;nready_valid=ready_valid;
        if (wr_done) begin nready=wr_bank;nready_valid=1;end
        if (rd_boundary && !freeze && nready_valid) begin
            nr=nready;nvalid=1;nready_valid=0;
        end
        if (wr_done) begin
            // Highest available bank is selected deterministically.
            for(i=0;i<3;i=i+1)
                if (i!=nr && (!nready_valid || i!=nready)) nw=i[1:0];
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_bank<=0;rd_bank<=1;ready_bank<=2;rd_valid<=0;ready_valid<=0;
            completed_frames<=0;selected_frames<=0;
        end else begin
            wr_bank<=nw;rd_bank<=nr;ready_bank<=nready;
            rd_valid<=nvalid;ready_valid<=nready_valid;
            if (wr_done) completed_frames<=completed_frames+1'b1;
            if (rd_boundary && !freeze && nready_valid==0 && (ready_valid || wr_done))
                selected_frames<=selected_frames+1'b1;
        end
    end
    assign wr_addr=wr_bank*FRAME_STRIDE;
    assign rd_addr=rd_bank*FRAME_STRIDE;
endmodule

`default_nettype wire
