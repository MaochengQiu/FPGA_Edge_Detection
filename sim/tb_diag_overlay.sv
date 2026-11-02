`timescale 1ns/1ps
// V6 integration test: 2x-scale white glyphs, dark shadow, transparency,
// original HS/VS/DE transparency, modes 0/3/6 vs legacy mode 2.
// Uses a 1280x120 synthetic raster and never alters PLL/DDR/HDMI IP.
module tb_diag_overlay;
    localparam W=1280,H=120;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0;
    reg [23:0] rgb=24'h5c6789;
    reg [2:0] mode=3'd6;
    wire [23:0] o6,o2;
    wire de6,hs6,vs6,de2,hs2,vs2;
    edge_diag_page #(.WIDTH(W),.HEIGHT(H)) d6(
       .clk(clk),.rst_n(rst_n),.de(de),.hs(hs),.vs(vs),.in_rgb(rgb),
       .display_mode(mode),.preprocess_mode(2'd3),.threshold(11'h028),
       .key_press_count(8'h0a),.last_key(2'd2),
       .wb_r(10'h100),.wb_g(10'h120),.wb_b(10'h0e0),.wb_selected(2'd1),
       .mean_raw_r(8'hc0),.mean_raw_g(8'h88),.mean_raw_b(8'hd0),
       .mean_bal_r(8'hc0),.mean_bal_g(8'ha0),.mean_bal_b(8'hb8),
       .sample_valid(1'b1),.last_samples(9'h100),
       .cam_bcd(8'h30),.done_bcd(8'h29),.selected_bcd(8'h28),
       .reject_flag(1'b0),.late_flag(1'b1),.overflow_flag(1'b0),.freeze_active(1'b0),
       .out_rgb(o6),.out_de(de6),.out_hs(hs6),.out_vs(vs6));
    edge_diag_page #(.WIDTH(W),.HEIGHT(H)) d2(
       .clk(clk),.rst_n(rst_n),.de(de),.hs(hs),.vs(vs),.in_rgb(rgb),
       .display_mode(3'd2),.preprocess_mode(2'd3),.threshold(11'h028),
       .key_press_count(8'h0a),.last_key(2'd2),
       .wb_r(10'h100),.wb_g(10'h120),.wb_b(10'h0e0),.wb_selected(2'd1),
       .mean_raw_r(8'hc0),.mean_raw_g(8'h88),.mean_raw_b(8'hd0),
       .mean_bal_r(8'hc0),.mean_bal_g(8'ha0),.mean_bal_b(8'hb8),
       .sample_valid(1'b1),.last_samples(9'h100),
       .cam_bcd(8'h30),.done_bcd(8'h29),.selected_bcd(8'h28),
       .reject_flag(1'b0),.late_flag(1'b1),.overflow_flag(1'b0),.freeze_active(1'b0),
       .out_rgb(o2),.out_de(de2),.out_hs(hs2),.out_vs(vs2));
    integer white_count=0,shadow_count=0,untouched_count=0;
    task send(input integer enable,input integer hsync,input integer vsync,
              input integer xpos,input integer ypos);
        begin
            @(negedge clk);
            de=enable;hs=hsync;vs=vsync;
            @(posedge clk);#1;
            if(de6!==enable[0] || hs6!==hsync[0] || vs6!==vsync[0] ||
               de2!==enable[0] || hs2!==hsync[0] || vs2!==vsync[0])
               $fatal(1,"out DE/HS/VS must all be aligned with registered RGB");
            if(enable)begin
                if(o2!==rgb)$fatal(1,"legacy mode 2 altered video");
                if(xpos>1040 || ypos>=80)begin
                    if(o6!==rgb)$fatal(1,"overlay changed pixels outside text at %0d,%0d",xpos,ypos);
                    untouched_count=untouched_count+1;
                end
                if(xpos>=24 && xpos<1016 && ypos>=14 && ypos<62)begin
                    if(o6===24'hffffff)white_count=white_count+1;
                    if(o6===24'h111820)shadow_count=shadow_count+1;
                end
            end else if(o6!==0 || o2!==0)
                $fatal(1,"nonactive video must be black");
        end
    endtask
    integer x,y;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        send(0,0,1,0,0);send(0,0,1,0,0);send(0,0,0,0,0);
        for(y=0;y<85;y=y+1)begin
            for(x=0;x<W;x=x+1)send(1,0,0,x,y);
            send(0,1,0,0,y);
            send(0,0,0,0,y);
        end
        if(white_count<100 || shadow_count<40 || untouched_count<1000)
            $fatal(1,"missing white/shadow/non-covered video pixels");
        $display("V6 OVERLAY PASS white=%0d shadow=%0d untouched=%0d",white_count,shadow_count,untouched_count);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
