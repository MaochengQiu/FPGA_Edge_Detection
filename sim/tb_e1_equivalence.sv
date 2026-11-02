`timescale 1ns/1ps
// Compare the unedited C2 kernel with E1's original Sobel branch, token for
// token after the documented extra delay. Also check NMS never adds an edge.
module tb_e1_equivalence;
    parameter integer W=32,H=12,HT=40;
    localparam EXTRA=3*HT+38,L=5*HT+60;
    reg clk=0,rst=0,de=0,hs=0,vs=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg [1:0] pre=0;reg [2:0] mode=0;reg [10:0] t=24;
    wire [23:0] base,raw,nms;wire bd,bh,bv,rd,rh,rv,nd,nh,nv;
    wire [10:0] rawmag,nmsmag;wire rawedge,nmsedge;
    wire [26:0] delayed_base;wire [2:0] aligned_mode;
    wire [15:0] ox,oy;wire us,ue;
    img_pipeline_c2_reference #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT)) baseline(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(t),.cfg_display(mode),
        .out_rgb(base),.out_de(bd),.out_hs(bh),.out_vs(bv));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(0),.COMPARE_PAIR_EDGE(0)) bypass(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(t),.cfg_display(mode),
        .out_rgb(raw),.out_de(rd),.out_hs(rh),.out_vs(rv),.debug_magnitude(rawmag),.debug_edge(rawedge));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(1)) experimental(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(t),.cfg_display(mode),
        .out_rgb(nms),.out_de(nd),.out_hs(nh),.out_vs(nv),.debug_magnitude(nmsmag),.debug_edge(nmsedge));
    img_delay #(.BITS(27),.CYCLES(EXTRA)) old_alignment(
        .clk(clk),.rst_n(rst),.din({bv,bh,bd,base}),.dout(delayed_base));
    img_delay #(.BITS(3),.CYCLES(L)) mode_alignment(
        .clk(clk),.rst_n(rst),.din(mode),.dout(aligned_mode));
    img_coords #(.WIDTH(W),.HEIGHT(H)) output_coords(.clk(clk),.rst_n(rst),.de(rd),.vs(rv),
        .x(ox),.y(oy),.sof(us),.eol(ue));
    integer checks=0,before_edges=0,after_edges=0,m5_checks=0,left_checks=0;
    always @(posedge clk)if(rst)begin
        #1;
        if({rv,rh,rd,raw}!==delayed_base)$fatal(1,"E1 Sobel bypass differs from immutable C2");
        if({nv,nh,nd}!={rv,rh,rd})$fatal(1,"NMS A/B sync differs");
        if(nmsmag!==rawmag)$fatal(1,"NMS changed original gradient amplitude");
        if(nmsedge && !rawedge)$fatal(1,"NMS added an unthresholded edge");
        if(rawedge)before_edges=before_edges+1;
        if(nmsedge)after_edges=after_edges+1;
        if(rd)begin
            if(aligned_mode==0||aligned_mode==1||aligned_mode==5||aligned_mode==6)begin
                if(nms!==raw)$fatal(1,"NMS altered RGB/gray/M5/diagnostic content");
                if(aligned_mode==5)m5_checks=m5_checks+1;
            end
            if(aligned_mode==3 && ox<(W+1)/2)begin
                if(nms!==raw)$fatal(1,"M3 original image changed");left_checks=left_checks+1;
            end
        end
        checks=checks+1;
    end
    integer f,x,y,p;reg [7:0] r,g,b;
    initial begin
        repeat(4)@(negedge clk);rst=1;
        for(f=0;f<112;f=f+1)begin
            pre=(f/7)%4;mode=f%7;t=(f%5==0)?128:24;
            for(y=0;y<H+12;y=y+1)for(x=0;x<HT;x=x+1)begin
                de=y>=2 && y<H+2 && x<W;hs=x==W+2;vs=y==0;
                r=x*17+y*3+f;g=x*3+y*23;b=x*13+y*7+f;
                case(f%4)
                    0:begin p=x<W/2?16:24;r=p;g=p;b=p;end
                    1:begin p=(x/4+y/4)%2?192:32;r=p;g=p;b=p;end
                    2:begin p=x<y?80:200;r=p;g=p;b=p;end
                endcase
                rgb={r,g,b};@(negedge clk);
            end
        end
        de=0;hs=0;vs=0;repeat(L+4)@(negedge clk);
        if(before_edges==0||after_edges==0||after_edges>=before_edges||m5_checks<10||left_checks<10)
            $fatal(1,"insufficient equivalence/edge coverage");
        $display("E1 EQUIVALENCE PASS W=%0d H=%0d checks=%0d Sobel=%0d NMS=%0d M5=%0d left=%0d, C2 bit-exact bypass after %0d clocks, identical A/B sync",W,H,checks,before_edges,after_edges,m5_checks,left_checks,EXTRA);$finish;
    end
    initial begin #100000000;$fatal(1,"E1 equivalence timeout");end
endmodule
