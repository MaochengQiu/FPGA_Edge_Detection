`timescale 1ns/1ps
module tb_frame_manager;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,done=0,boundary=0,freeze=0;
    wire [1:0] wb,rb;wire valid;wire [31:0] wa,ra,complete,selected;
    img_frame_manager #(.FRAME_STRIDE(4096)) dut(.clk(clk),.rst_n(rst_n),
        .wr_done(done),.rd_boundary(boundary),.freeze(freeze),.wr_bank(wb),.rd_bank(rb),
        .rd_valid(valid),.wr_addr(wa),.rd_addr(ra),.completed_frames(complete),.selected_frames(selected));
    integer i;reg [1:0] old_rd;integer seed=4321;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        // Every combination, then random history with simultaneous requests.
        for(i=0;i<10008;i=i+1) begin
            done=i<8?i[0]:($random(seed)&1);
            boundary=i<8?i[1]:($random(seed)&1);
            freeze=i<8?i[2]:($random(seed)&1);
            old_rd=rb;@(posedge clk);#1;
            if(wb==rb || wb>2 || rb>2) $fatal(1,"ownership collision");
            if(dut.ready_valid && (dut.ready_bank==wb || dut.ready_bank==rb)) $fatal(1,"ready collision");
            if(freeze && rb!=old_rd) $fatal(1,"frozen bank changed");
            if(wa!=wb*4096 || ra!=rb*4096) $fatal(1,"address mapping");
            @(negedge clk);
        end
        $display("FRAME MANAGER PASS 10008 transitions");$finish;
    end
endmodule
