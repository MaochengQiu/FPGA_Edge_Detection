`timescale 1ns/1ps
module tb_axi_reader_pending;
    reg clk=0,rst=0,request=0,ready=0;always #5 clk=~clk;
    wire fv;wire [128:0] fd;wire [31:0] addr;wire [7:0] len;
    wire [2:0] size;wire [1:0] burst;wire av,rr,boundary;
    wire [31:0] late,errors;
    reg rv=0,rl=0;reg [127:0] data=0;
    img_axi_reader #(.FRAME_BEATS(8),.MAX_BURST(4)) dut(
        .clk(clk),.rst_n(rst),.request(request),.frame_addr(32'd0),.frame_valid(1'b1),
        .fifo_valid(fv),.fifo_ready(ready),.fifo_data(fd),.araddr(addr),.arlen(len),
        .arsize(size),.arburst(burst),.arvalid(av),.arready(1'b1),
        .rdata(data),.rvalid(rv),.rlast(rl),.rresp(2'd0),.rready(rr),
        .boundary(boundary),.late_requests(late),.read_errors(errors));
    integer left=0,boundaries=0,received=0;
    always @(posedge clk)if(rst)begin
        if(boundary)boundaries=boundaries+1;
        if(av)left=len+1;
        if(rv && rr)begin left=left-1;received=received+1;end
        rv<=left>0;rl<=left==1;data<=data+1'b1;
    end
    initial begin
        repeat(4)@(negedge clk);rst=1;request=1;
        @(negedge clk);request=0;wait(rv);
        @(negedge clk);request=1;@(negedge clk);request=0;
        repeat(10)@(negedge clk);ready=1;
        wait(received==16);repeat(6)@(negedge clk);
        if(boundaries!=2 || late!=1 || errors!=0)$fatal(1,"lost pending request");
        $display("AXI READER PASS busy request retained and started after previous DMA");$finish;
    end
    initial begin #100000;$fatal(1,"reader timeout");end
endmodule
