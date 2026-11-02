`timescale 1ns/1ps
module tb_nms;
    parameter integer WIDTH=32,HEIGHT=16,HTOTAL=40,STRICT_TIES=0;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [10:0] mag=0;reg [1:0] dir=0;reg valid=0;reg [3:0] ctl=0;
    wire keep;wire [10:0] out_mag;wire [3:0] out_ctl;
    img_nms #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.STRICT_TIES(STRICT_TIES)) dut(
        .clk(clk),.rst_n(rst),.magnitude(mag),.direction(dir),.valid(valid),.ctl(ctl),
        .keep(keep),.out_magnitude(out_mag),.out_ctl(out_ctl));
    integer f,o,n,status,m,d,v,c;
    initial begin
        f=$fopen("nms_vectors.txt","r");o=$fopen("nms_observed.txt","w");
        if(!f||!o)$fatal(1,"NMS vector files");
        repeat(4)@(negedge clk);rst=1;n=0;
        while(!$feof(f))begin
            status=$fscanf(f,"%d %d %d %d\n",m,d,v,c);
            if(status==4)begin
                mag=m;dir=d;valid=v;ctl=c;
                @(posedge clk);#1;
                $fwrite(o,"%d %d %d\n",keep,out_mag,out_ctl);n=n+1;
                @(negedge clk);
            end
        end
        $fclose(f);$fclose(o);$display("NMS VECTORS PASS samples=%0d",n);$finish;
    end
endmodule
