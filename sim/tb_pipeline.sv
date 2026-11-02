`timescale 1ns/1ps
module tb_pipeline;
    parameter integer WIDTH=8,HEIGHT=6,HTOTAL=12;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;reg [23:0] rgb=0;reg de=0,hs=0,vs=0;
    reg [1:0] pre=0;reg [2:0] display=0;reg [10:0] threshold=0;
    wire [23:0] out_rgb;wire od,oh,ov;wire [10:0] mag;wire edge_bit,sof;
    img_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL)) dut(
        .clk(clk),.rst_n(rst_n),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(threshold),.cfg_display(display),
        .out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov),
        .debug_magnitude(mag),.debug_edge(edge_bit),.input_sof(sof));
    integer f,o,status,index;integer a,b,c,d,e,g;reg [23:0] color;
    initial begin
        f=$fopen("stimulus.txt","r");o=$fopen("observed.txt","w");
        if (!f || !o) $fatal(1,"cannot open stimulus/output");
        repeat(4) @(negedge clk);rst_n=1;index=0;
        while(!$feof(f)) begin
            status=$fscanf(f,"%h %d %d %d %d %d %d\n",color,a,b,c,d,e,g);
            if(status==7) begin
                rgb=color;de=a;hs=b;vs=c;pre=d;display=e;threshold=g;
                @(posedge clk);#1;
                $fwrite(o,"%06h %0d %0d %0d\n",out_rgb,od,oh,ov);
                index=index+1;@(negedge clk);
            end
        end
        $fclose(f);$fclose(o);$display("PIPELINE samples=%0d",index);$finish;
    end
endmodule
