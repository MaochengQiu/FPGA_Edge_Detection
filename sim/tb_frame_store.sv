`timescale 1ns/1ps
module tb_frame_store;
    parameter integer CAM_VS_LEVEL=0;
    localparam integer WIDTH=64,HEIGHT=130,PIXELS=WIDTH*HEIGHT,WORDS=PIXELS/2;
    reg cc=0,ac=0,oc=0;always #7 cc=~cc;always #5 ac=~ac;always #11 oc=~oc;
    reg reset=0;wire cr,ar,orr;
    img_reset_sync cs(.clk(cc),.arst_n(reset),.rst_n(cr));
    img_reset_sync asy(.clk(ac),.arst_n(reset),.rst_n(ar));
    img_reset_sync os(.clk(oc),.arst_n(reset),.rst_n(orr));
    reg cvs=0,cde=0;reg [31:0] cd=0;reg freeze=0,request=0;
    wire [15:0] od;wire valid,sof,eol;reg ready=0;
    wire [31:0] awa,ara;wire [7:0] awl,arl;wire [2:0] aws,ars;
    wire [1:0] awb,arb;wire awv,wv,wl,br,arv,rr;
    wire [127:0] wd;reg awready=0,wready=0,bvalid=0;
    reg [1:0] bresp=0,rresp=0;reg arready=0,rvalid=0,rlast=0;reg [127:0] rd=0;
    wire [31:0] complete,rejected,late,errors,overflow;
    img_frame_store #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FIFO_DEPTH(128),.MAX_BURST(37)) dut(
        .cam_clk(cc),.cam_rst_n(cr),.cam_vs(cvs),.cam_de(cde),.cam_data(cd),
        .axi_clk(ac),.axi_rst_n(ar),.freeze(freeze),.out_clk(oc),.out_rst_n(orr),.frame_request(request),
        .out_data(od),.out_valid(valid),.out_ready(ready),.out_sof(sof),.out_eol(eol),
        .awaddr(awa),.awlen(awl),.awsize(aws),.awburst(awb),.awvalid(awv),.awready(awready),
        .wdata(wd),.wvalid(wv),.wlast(wl),.wready(wready),.bvalid(bvalid),.bresp(bresp),.bready(br),
        .araddr(ara),.arlen(arl),.arsize(ars),.arburst(arb),.arvalid(arv),.arready(arready),
        .rdata(rd),.rvalid(rvalid),.rlast(rlast),.rresp(rresp),.rready(rr),
        .completed_frames(complete),.rejected_frames(rejected),.late_requests(late),.read_errors(errors),.capture_overflows(overflow));
    reg [127:0] memory[0:3071];
    integer wt=0,wa=0,wn=0,wi=0,btimer=0;
    integer rt=0,ra=0,rn=0,ri=0;reg writing=0,reading=0;
    reg inject_b_error=0;reg [31:0] held_aw,held_ar;reg [127:0] held_w;
    reg stall_aw=0,stall_w=0,stall_ar=0;
    always @(negedge ac) begin
        awready=!writing && !bvalid && btimer==0 && wt%4!=0;
        wready=writing && wt%5!=0;
        arready=!reading && !rvalid && rt%3!=0;
        wt=wt+1;rt=rt+1;
    end
    always @(posedge ac) if(ar) begin
        if(stall_aw && (!awv || awa!=held_aw)) $fatal(1,"AW stability");
        if(stall_w && (!wv || wd!==held_w)) $fatal(1,"W stability");
        if(stall_ar && (!arv || ara!=held_ar)) $fatal(1,"AR stability");
        stall_aw=awv && !awready;held_aw=awa;
        stall_w=wv && !wready;held_w=wd;
        stall_ar=arv && !arready;held_ar=ara;
        if(awv && awready) begin
            if(aws!=4 || awb!=1 || awa%16!=0 || (awa%4096)+(awl+1)*16>4096) $fatal(1,"illegal write burst");
            writing=1;wa=awa/16;wn=awl+1;wi=0;
        end
        if(wv && wready) begin
            if(!writing || wl!=(wi==wn-1)) $fatal(1,"WLAST mismatch");
            memory[wa+wi]=wd;wi=wi+1;
            if(wl) begin writing=0;btimer=4;end
        end
        if(bvalid && br) begin bvalid<=0;bresp<=0;end
        if(btimer>0) begin
            btimer=btimer-1;
            if(btimer==0) begin bvalid<=1;bresp<=inject_b_error?2'd2:2'd0;end
        end
        if(arv && arready) begin
            if(ars!=4 || arb!=1 || ara%16!=0 || (ara%4096)+(arl+1)*16>4096) $fatal(1,"illegal read burst");
            reading=1;ra=ara/16;rn=arl+1;ri=0;
        end
        if(rvalid && rr) begin
            rvalid<=0;ri=ri+1;
            if(ri==rn) reading=0;
        end
        if(reading && (!rvalid || rr) && rt%4!=0) begin
            rd<=memory[ra+ri];rvalid<=1;rlast<=(ri==rn-1);rresp<=0;
        end
    end
    task capture(input integer frame,input integer count);
        integer j,k;reg [31:0] value;
        begin
            @(negedge cc);cvs=1;cde=0;repeat(6) @(negedge cc);if(!CAM_VS_LEVEL)cvs=0;
            repeat(3) @(negedge cc);
            for(j=0;j<count;j=j+1) begin
                value=0;for(k=0;k<4;k=k+1)value[k*8+:8]=(frame*17+j*4+k)%256;
                cd=value;cde=1;@(negedge cc);
                if(j%16==15) begin cde=0;repeat(3) @(negedge cc);end
            end
            cde=0;cvs=0;repeat(20) @(negedge cc);
        end
    endtask
    task display_frame(input integer frame,input integer black);
        integer j,t;reg [15:0] expected;
        begin
            @(negedge oc);request=1;repeat(8) @(negedge oc);request=0;
            j=0;t=0;
            while(j<WORDS) begin
                ready=(t%6!=0);@(posedge oc);
                if(valid && ready) begin
                    expected=black?16'd0:(((frame*17+j*2+1)%256)<<8)|((frame*17+j*2)%256);
                    if(od!==expected || sof!=(j==0) || eol!=(j%(WIDTH/2)==WIDTH/2-1))
                        $fatal(1,"frame %0d word %0d got %h expected %h sof %b eol %b",frame,j,od,expected,sof,eol);
                    j=j+1;
                end
                @(negedge oc);t=t+1;
                if(t>50000) $fatal(1,"display timeout");
            end
            ready=0;repeat(20) @(negedge oc);
        end
    endtask
    initial begin
        repeat(5) @(negedge ac);reset=1;repeat(20) @(negedge ac);
        @(negedge cc);cvs=1;repeat(6) @(negedge cc);cvs=0;repeat(4) @(negedge cc);
        display_frame(0,1); // black initialization, no read of uninitialized DDR
        capture(1,PIXELS/4);wait(complete==1);display_frame(1,0);
        freeze=1;repeat(10) @(negedge ac);
        capture(2,PIXELS/4);wait(complete==2);display_frame(1,0);
        capture(3,PIXELS/4);wait(complete==3);display_frame(1,0);
        freeze=0;repeat(10) @(negedge ac);display_frame(3,0);
        inject_b_error=1;capture(4,PIXELS/4);wait(rejected==1);inject_b_error=0;
        if(complete!=3) $fatal(1,"failed AXI write published");
        display_frame(3,0);
        // A truncated camera frame must not publish; the next SOF permits recovery.
        capture(5,PIXELS/8);capture(6,PIXELS/4);wait(complete==4);display_frame(6,0);
        if(overflow!=0 || errors!=0 || late!=0 || rejected!=2) $fatal(1,"unexpected status %0d %0d %0d %0d",overflow,errors,late,rejected);
        $display("FRAME STORE PASS initialization/capture/freeze/latest/recovery/B-error/stalls/4KiB");$finish;
    end
    initial begin #5000000;$fatal(1,"frame store timeout complete=%0d rejected=%0d",complete,rejected);end
endmodule
