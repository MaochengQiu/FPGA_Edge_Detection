`timescale 1ns/1ps
module tb_operators;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;reg [71:0] pixels=0;
    wire [7:0] median,gauss;wire signed [10:0] gx,gy;wire [10:0] mag;
    img_median9 m(.clk(clk),.rst_n(rst_n),.pixels(pixels),.median(median));
    img_gaussian3x3 g(.clk(clk),.rst_n(rst_n),.pixels(pixels),.pixel(gauss));
    img_sobel_gradient s(.clk(clk),.rst_n(rst_n),.pixels(pixels),.gx(gx),.gy(gy),.magnitude(mag));
    integer f,o,n,status;
    initial begin
        f=$fopen("operator_input.txt","r");o=$fopen("operator_output.txt","w");
        repeat(4) @(negedge clk);rst_n=1;n=0;
        while(!$feof(f)) begin
            status=$fscanf(f,"%h\n",pixels);
            if(status==1) begin
                @(posedge clk);#1;
                $fwrite(o,"%0d %0d %0d %0d %0d\n",median,gauss,gx,gy,mag);
                n=n+1;@(negedge clk);
            end
        end
        $display("OPERATORS samples=%0d",n);$finish;
    end
endmodule
