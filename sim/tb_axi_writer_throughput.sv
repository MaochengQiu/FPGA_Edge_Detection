`timescale 1ns/1ps
module tb_axi_writer_throughput;
    reg clk=0,rst=0;always #5 clk=~clk;
    localparam N=32;
    reg fv=0;wire fr;integer index=0,frame=1;
    wire [129:0] fd={index==N-1,index==0,96'd0,frame[15:0],index[15:0]};
    wire [31:0] awa;wire [7:0] awl;wire [2:0] aws;wire [1:0] awb;
    wire av,wv,wl,br,done;wire [127:0] wd;wire [31:0] rejected;
    reg ar=0,wr=0,bv=0;reg [1:0] resp=0;reg error_mode=0;
    img_axi_writer #(.FRAME_BEATS(N),.MAX_BURST(4),.MAX_OUTSTANDING(4)) dut(
        .clk(clk),.rst_n(rst),.frame_addr(32'h1000),.fifo_valid(fv),.fifo_ready(fr),.fifo_data(fd),
        .awaddr(awa),.awlen(awl),.awsize(aws),.awburst(awb),.awvalid(av),.awready(ar),
        .wdata(wd),.wvalid(wv),.wlast(wl),.wready(wr),.bvalid(bv),.bresp(resp),.bready(br),
        .frame_done(done),.rejected_frames(rejected));
    integer cycle=0,acount=0,bcount=0,head=0,tail=0,beats=0,max_pending=0;
    integer due[0:31];reg [1:0] response[0:31];reg writing=0,pipelined=0;
    always @(negedge clk)begin ar=!writing && cycle%5!=0;wr=writing && cycle%7!=0;end
    always @(posedge clk)if(rst)begin
        cycle=cycle+1;
        if(bv && br)begin bcount=bcount+1;head=head+1;bv<=0;end
        if(!bv && head<tail && due[head]<=cycle)begin bv<=1;resp<=response[head];end
        if(av && ar)begin
            if(aws!=4 || awb!=1 || awl!=3)$fatal(1,"bad AW");
            if(acount>bcount)pipelined=1;
            acount=acount+1;writing=1;beats=0;
            if(acount-bcount>max_pending)max_pending=acount-bcount;
        end
        if(wv && wr)begin
            if(!writing || wl!=(beats==3))$fatal(1,"W burst sequence");
            beats=beats+1;
            if(wl)begin writing=0;due[tail]=cycle+50;response[tail]=error_mode?2'd2:2'd0;tail=tail+1;end
        end
        if(fv && fr)begin
            if(index==N-1)begin fv<=0;index<=0;end else index<=index+1;
        end
        if(done && acount!=bcount)$fatal(1,"published before all responses");
    end
    initial begin
        repeat(4)@(negedge clk);rst=1;fv=1;
        wait(done);@(negedge clk);
        if(!pipelined || max_pending!=4 || rejected!=0)$fatal(1,"no response pipeline");
        repeat(4)@(negedge clk);frame=2;error_mode=1;fv=1;
        wait(rejected==1);@(negedge clk);
        if(done || acount!=bcount)$fatal(1,"bad frame published or undrained");
        $display("AXI WRITER PASS 4 outstanding delayed responses, ordered W, error rejection, drain-before-publish");$finish;
    end
    initial begin #100000;$fatal(1,"writer timeout");end
endmodule
