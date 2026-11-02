`timescale 1ns/1ps
module tb_local_link;
    parameter integer WIDTH=32,HEIGHT=20,HTOTAL=40,BRIDGE_ENABLE=1,WEAK_CHAIN_ENABLE=0;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [4:0] descriptor=0;reg [3:0] ctl=0;
    wire edge_pixel;wire [3:0] out_ctl;
    img_edge_link #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.BRIDGE_ENABLE(BRIDGE_ENABLE),.WEAK_CHAIN_ENABLE(WEAK_CHAIN_ENABLE)) dut(
        .clk(clk),.rst_n(rst),.descriptor(descriptor),.ctl(ctl),.edge_pixel(edge_pixel),.out_ctl(out_ctl));
    integer f,o,status,d,c,n;
    initial begin
        f=$fopen("link_vectors.txt","r");o=$fopen("link_observed.txt","w");
        if(!f||!o)$fatal(1,"link vectors");repeat(4)@(negedge clk);rst=1;n=0;
        while(!$feof(f))begin
            status=$fscanf(f,"%d %d\n",d,c);
            if(status==2)begin
                descriptor=d;ctl=c;@(posedge clk);#1;
                $fwrite(o,"%d %d\n",edge_pixel,out_ctl);n=n+1;@(negedge clk);
            end
        end
        $fclose(f);$fclose(o);$display("LOCAL LINK PASS W=%0d H=%0d bridge=%0d samples=%0d",WIDTH,HEIGHT,BRIDGE_ENABLE,n);$finish;
    end
endmodule
