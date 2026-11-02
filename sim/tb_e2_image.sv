`timescale 1ns/1ps
module tb_e2_image;
    parameter integer WIDTH=256,HEIGHT=192,HTOTAL=288,LINK_ENABLE=1,HIGH=50,WEAK_CHAIN_ENABLE=0;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg de=0,hs=0,vs=0;wire [23:0] out_rgb;wire od,oh,ov;
    img_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.NMS_ENABLE(1),.LINK_ENABLE(LINK_ENABLE),.WEAK_CHAIN_ENABLE(WEAK_CHAIN_ENABLE)) dut(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(2'd0),.cfg_threshold(11'(HIGH)),.cfg_display(3'd2),
        .out_rgb(out_rgb),.out_de(od),.out_hs(oh),.out_vs(ov));
    integer f,o,status,n,a,b,c;reg [23:0] color;
    initial begin
        f=$fopen("e2_vectors.txt","r");o=$fopen("e2_observed.txt","w");
        if(!f||!o)$fatal(1,"E2 fixtures");repeat(4)@(negedge clk);rst=1;n=0;
        while(!$feof(f))begin
            status=$fscanf(f,"%h %d %d %d\n",color,a,b,c);
            if(status==4)begin
                rgb=color;de=a;hs=b;vs=c;@(posedge clk);#1;
                $fwrite(o,"%06h %d %d %d\n",out_rgb,od,oh,ov);n=n+1;@(negedge clk);
            end
        end
        $fclose(f);$fclose(o);$display("E2 IMAGE PASS LINK=%0d HIGH=%0d samples=%0d",LINK_ENABLE,HIGH,n);$finish;
    end
endmodule
