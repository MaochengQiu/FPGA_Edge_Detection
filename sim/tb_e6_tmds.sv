`timescale 1ps/1ps
module tb_e6_tmds;
    reg clk=0,rst=1;
    always #1000 clk=~clk;
    reg [23:0] rgb=0;
    reg de=0,hs=0,vs=0;
    wire [9:0] b,g,r,clock_word;
    reg [9:0] eb,eg,er;
    integer f,n,count=0;
    edge_dvi_encoder dut(.pixelclk(clk),.rst_p(rst),
        .i_bdata(rgb[7:0]),.i_gdata(rgb[15:8]),.i_rdata(rgb[23:16]),
        .i_de(de),.i_hs(hs),.i_vs(vs),
        .tmds_data0(b),.tmds_data1(g),.tmds_data2(r),.tmds_clk(clock_word));
    initial begin
        f=$fopen("e6_tmds_vectors.txt","r");
        if(!f)$fatal(1,"Missing independent TMDS vectors");
        while(!$feof(f))begin
            @(negedge clk);
            n=$fscanf(f,"%h %h %h %h %h %h %h %h\n",rst,rgb,de,hs,vs,eb,eg,er);
            if(n!=8)$fatal(1,"Malformed vector %0d",count);
            @(posedge clk);#10;
            if({b,g,r}!=={eb,eg,er})
                $fatal(1,"TMDS mismatch cycle %0d actual %h/%h/%h expected %h/%h/%h",count,b,g,r,eb,eg,er);
            if(clock_word!==10'b1111100000)$fatal(1,"Clock word changed");
            count=count+1;
        end
        $fclose(f);
        $display("E6 TMDS PASS: %0d cycles, three lanes exact signed-disparity oracle, reset and blanking",count);
        $finish;
    end
endmodule
