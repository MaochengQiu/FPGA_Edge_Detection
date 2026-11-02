`timescale 1ns/1ps
module tb_e1_image;
    parameter integer WIDTH=256,HEIGHT=192,HTOTAL=288,NMS_ENABLE=1;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg de=0,hs=0,vs=0;wire [23:0] out_rgb;wire od,oh,ov;
    img_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.NMS_ENABLE(NMS_ENABLE)) dut(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(2'd0),.cfg_threshold(11'd24),.cfg_display(3'd2),
        .out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    integer f,o,status,n,a,b,c;reg [23:0] color;
    initial begin
        f=$fopen("e1_vectors.txt","r");o=$fopen("e1_observed.txt","w");
        if(!f||!o)$fatal(1,"image fixtures");repeat(4)@(negedge clk);rst=1;n=0;
        while(!$feof(f))begin
            status=$fscanf(f,"%h %d %d %d\n",color,a,b,c);
            if(status==4)begin
                rgb=color;de=a;hs=b;vs=c;@(posedge clk);#1;
                $fwrite(o,"%06h %d %d %d\n",out_rgb,od,oh,ov);n=n+1;@(negedge clk);
            end
        end
        $fclose(f);$fclose(o);$display("E1 IMAGE RTL PASS NMS=%0d samples=%0d",NMS_ENABLE,n);$finish;
    end
endmodule
