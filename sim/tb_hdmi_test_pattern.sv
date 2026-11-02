`timescale 1ns/1ps
module tb_hdmi_test_pattern;
    parameter W=64,H=48,HFP=6,HSP=4,HBP=6,VFP=2,VSP=2,VBP=4,FRAME_COUNT=20;
    localparam HT=W+HFP+HSP+HBP,VT=H+VFP+VSP+VBP,XS=HSP+HBP,YS=VSP+VBP;
    reg clk=0,rst=0;always #5 clk=~clk;
    wire [23:0] rgb;wire de,hs,vs;
    edge_hdmi_test_pattern #(.WIDTH(W),.HEIGHT(H),.HFP(HFP),.HSP(HSP),.HBP(HBP),.VFP(VFP),.VSP(VSP),.VBP(VBP)) dut(
        .clk(clk),.rst_n(rst),.rgb(rgb),.de(de),.hs(hs),.vs(vs));
    integer x=0,y=0,frames=0,checked=0,active_count=0,black=0,white=0,color=0;
    reg expected_de;
    always @(posedge clk)if(rst)begin
        expected_de=x>=XS && x<XS+W && y>=YS && y<YS+H;
        #1;
        if({hs,vs,de}!=={x<HSP,y<VSP,expected_de})$fatal(1,"test raster changed");
        if(de)begin
            active_count=active_count+1;
            if(rgb==0)black=black+1;
            else if(rgb==24'hffffff)white=white+1;
            else color=color+1;
        end else if(rgb!=0)$fatal(1,"nonzero blanking");
        checked=checked+1;
        if(x==HT-1)begin x=0;if(y==VT-1)begin y=0;frames=frames+1;end else y=y+1;end else x=x+1;
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        wait(frames==FRAME_COUNT);@(negedge clk);
        if(active_count!=FRAME_COUNT*W*H || black==0 || white==0 || color==0)$fatal(1,"pattern coverage");
        if(dut.frame!=FRAME_COUNT)$fatal(1,"frame animation stopped");
        $display("E4 HDMI TEST PASS W=%0d H=%0d exact raster, black/white/color patterns, %0d live frames, no camera/DDR dependency",W,H,FRAME_COUNT);$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
