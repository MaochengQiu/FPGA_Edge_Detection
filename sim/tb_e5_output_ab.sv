`timescale 1ns/1ps
module tb_e5_output_ab;
    localparam W=24,H=20,HT=32,L=5*HT+60;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg de=0,hs=0,vs=0;
    reg [1:0] pre=0;reg [10:0] threshold=58;
    wire [23:0] rgb2,rgb7;wire d2,h2,v2,d7,h7,v7,e2,e7;
    wire [10:0] mag2,mag7;
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(1),.LINK_ENABLE(1)) p2(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(threshold),.cfg_display(3'd2),
        .out_rgb(rgb2),.out_de(d2),.out_hs(h2),.out_vs(v2),.debug_edge(e2),.debug_magnitude(mag2));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(1),.LINK_ENABLE(1)) p7(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(threshold),.cfg_display(3'd7),
        .out_rgb(rgb7),.out_de(d7),.out_hs(h7),.out_vs(v7),.debug_edge(e7),.debug_magnitude(mag7));
    integer checked=0,white=0,black=0;
    always @(posedge clk)if(rst)begin
        #1;
        if({d2,h2,v2}!=={d7,h7,v7})$fatal(1,"M2/M7 sync differs");
        if({e2,mag2}!=={e7,mag7})$fatal(1,"display page altered algorithm");
        if(d2)begin
            if(rgb2!==0 && rgb2!==24'hffffff)$fatal(1,"M2 is not binary");
            if(rgb7!==(rgb2==24'hffffff ? 24'he0f0ff : 24'h000103))$fatal(1,"M7 edge map differs");
            if(rgb2==0)black=black+1;else white=white+1;
        end else if(rgb2!==0 || rgb7!==0)$fatal(1,"blanking changed");
        checked=checked+1;
    end
    integer f,x,y;reg [7:0] g;reg [31:0] rng=32'h57105868;
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(f=0;f<12;f=f+1)begin
            pre=f%4;
            case(f%3)0:threshold=58;1:threshold=68;2:threshold=47;endcase
            for(y=0;y<H+16;y=y+1)for(x=0;x<HT;x=x+1)begin
                @(negedge clk);
                de=y>=2 && y<H+2 && x<W;hs=x==W+2;vs=y==0;
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                case(f%3)
                    0:g=x<W/2?16:240;
                    1:g=((x/3+y/3)%2)?200:32;
                    2:g=rng[7:0];
                endcase
                rgb=de?{g,g,g}:0;
            end
        end
        @(negedge clk);rgb=0;de=0;hs=0;vs=0;
        repeat(L+8)@(negedge clk);
        if(white==0 || black==0 || checked<12000)$fatal(1,"missing coverage");
        $display("E5 OUTPUT AB PASS 12 frames, PRE0..3/T47/58/68, identical edge/magnitude/sync, only RGB codes differ; white=%0d black=%0d",white,black);$finish;
    end
    initial begin #1000000;$fatal(1,"AB timeout");end
endmodule
