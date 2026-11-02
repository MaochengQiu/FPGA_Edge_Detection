`timescale 1ns/1ps
// Fault injection at the real fixed-raster input seam, through the real E2L
// core and controller. Demonstrates content-blackout with UI retained; it
// does not claim to reproduce an electrical HDMI link loss on the board.
module tb_m2_starvation;
    localparam W=20,H=16,HT=28,VT=22,L=5*HT+60;
    reg clk=0,rst=0;always #5 clk=~clk;
    integer sx=0,sy=0,raster_frame=0;
    wire ready,request,de,hs,vs,uf;
    wire [7:0] raw;
    wire [31:0] dropped,shown;
    wire fault=raster_frame==3 && video.h==4 && video.v==4;
    wire valid=!fault;
    wire [7:0] source=(sx<W/2)?8'd24:8'd200;
    img_video_out #(.DATA_BITS(8),.PIXELS_PER_CLOCK(1),.WIDTH(W),.HEIGHT(H),
        .HFP(4),.HSP(2),.HBP(2),.VFP(2),.VSP(2),.VBP(2)) video(
        .clk(clk),.rst_n(rst),.in_data(source),.in_valid(valid),.in_sof(sx==0 && sy==0),.in_eol(sx==W-1),
        .in_ready(ready),.frame_request(request),.out_data(raw),.out_de(de),.out_hs(hs),.out_vs(vs),
        .underflow_sticky(uf),.underflow_frames(dropped),.displayed_frames(shown));
    reg wr=0;reg [1:0] addr=0;reg [10:0] data=0;
    wire [10:0] threshold,pending;wire [1:0] pre;wire [2:0] mode;
    wire sof;wire [23:0] pixel;wire od,oh,ov;
    img_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(20),.THRESHOLD_DEFAULT(50)) ctl(
        .clk(clk),.rst_n(rst),.keys_n(3'b111),.frame_sof(sof),.cfg_wr(wr),.cfg_addr(addr),.cfg_data(data),
        .threshold(threshold),.pending_threshold(pending),.preprocess(pre),.display(mode));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(1),.LINK_ENABLE(1)) core(
        .clk(clk),.rst_n(rst),.in_rgb({raw,raw,raw}),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_threshold(threshold),.cfg_preprocess(pre),.cfg_display(mode),.input_sof(sof),
        .out_rgb(pixel),.out_de(od),.out_hs(oh),.out_vs(ov));
    reg [L-1:0] expected_de=0,expected_hs=0,expected_vs=0;
    reg ov_q=0,configured=0;
    integer out_frame=0,white=0,frames[0:9],cycles_checked=0;
    reg consumed=0;
    always @(negedge clk)if(rst && consumed)begin
        if(sx==W-1)begin sx=0;if(sy==H-1)sy=0;else sy=sy+1;end else sx=sx+1;
    end
    always @(posedge clk)if(rst)begin
        if(request)raster_frame=raster_frame+1;
        consumed=ready && valid;
        expected_de<={expected_de[L-2:0],de};
        expected_hs<={expected_hs[L-2:0],hs};
        expected_vs<={expected_vs[L-2:0],vs};
        #1;
        if({od,oh,ov}!=={expected_de[L-1],expected_hs[L-1],expected_vs[L-1]})$fatal(1,"starvation changed output sync");
        if(threshold==68 && pre==1 && mode==2)configured=1;
        if(configured && (threshold!=68 || pre!=1 || mode!=2))$fatal(1,"starvation reset UI");
        if(ov && !ov_q)begin frames[out_frame]=white;out_frame=out_frame+1;white=0;end
        ov_q=ov;
        if(od && pixel!=0)white=white+1;
        cycles_checked=cycles_checked+1;
    end
    task set_cfg(input [1:0] a,input [10:0] v);
        begin @(negedge clk);addr=a;data=v;wr=1;@(negedge clk);wr=0;end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;
        set_cfg(0,68);set_cfg(1,1);set_cfg(2,2);
        wait(out_frame==7);@(negedge clk);
        if(!uf || dropped!=1 || !configured || frames[2]==0 || frames[3]!=0 || frames[4]==0)
            $fatal(1,"fault/recovery mismatch drops=%0d edges frames2/3/4=%0d/%0d/%0d",dropped,frames[2],frames[3],frames[4]);
        $display("M2 STARVATION PASS: injected one lost frame, black M2, T68/PRE1 retained, sync continuous, next frame recovered");$finish;
    end
    initial begin #1000000;$fatal(1,"starvation test timeout");end
endmodule
