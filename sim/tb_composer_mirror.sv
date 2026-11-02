`timescale 1ns/1ps
// Side-by-side mapping regression. No Efinix device IPs are required.
module tb_composer_mirror;
    parameter integer WIDTH=8,HEIGHT=5,PAIR_EDGE=1;
    localparam integer HALF=(WIDTH+1)/2;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg [3:0] ctl=0;
    reg [23:0] rgb=0;
    reg [7:0] gray=0;
    reg edge_pixel=0;
    reg [10:0] magnitude=0;
    reg [2:0] cfg_display=3;
    wire [23:0] out_rgb;
    wire [3:0] out_ctl;
    integer frame,x,y,src_x;
    reg [23:0] expected;
    img_composer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.PAIR_EDGE(PAIR_EDGE)) dut(
        .clk(clk),.rst_n(rst_n),.ctl(ctl),.rgb(rgb),.gray(gray),
        .edge_pixel(edge_pixel),.magnitude(magnitude),
        .cfg_display(cfg_display),.out_rgb(out_rgb),.out_ctl(out_ctl));
    function [23:0] make_rgb;
        input integer xx,yy,ff;
        begin make_rgb=((ff+1)<<20)|((yy+1)<<12)|((xx+1)<<4)|8'h05; end
    endfunction
    function edge_at;
        input integer xx,yy,ff;
        begin
            case(ff)
                0:edge_at=xx%2==1; // every edge is on an odd column
                1:edge_at=xx%2==0;
                default:edge_at=((xx+yy)%3)==1;
            endcase
        end
    endfunction
    task one_cycle;
        input [3:0] in_ctl;
        input [23:0] in_rgb;
        input in_edge;
        input [23:0] expectation;
        begin
            @(negedge clk);
            ctl=in_ctl;rgb=in_rgb;edge_pixel=in_edge;
            @(posedge clk);#1;
            if (out_ctl!==in_ctl) $fatal(1,"ctl timing input=%h observed=%h",in_ctl,out_ctl);
            if (in_ctl[0] && out_rgb!==expectation)
                $fatal(1,"mapping frame=%0d y=%0d x=%0d got=%06h exp=%06h",frame,y,x,out_rgb,expectation);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            one_cycle(4'b0100,0,0,0); // VS edge; reset x,y
            one_cycle(4'b0000,0,0,0);
            for(y=0;y<HEIGHT;y=y+1) begin
                for(x=0;x<WIDTH;x=x+1) begin
                    src_x=2*((x<HALF)?x:(x-HALF));
                    expected=0;
                    if (y>0) begin
                        if (x<HALF) expected=make_rgb(src_x,y-1,frame);
                        else expected=(edge_at(src_x,y-1,frame) ||
                            (PAIR_EDGE && src_x+1<WIDTH && edge_at(src_x+1,y-1,frame)))?24'hffffff:24'h000000;
                    end
                    one_cycle(4'b0001,make_rgb(x,y,frame),edge_at(x,y,frame),expected);
                end
                one_cycle(4'b0000,0,0,0);
                one_cycle(4'b0000,0,0,0);
            end
        end
        $display("COMPOSER MIRROR PASS WIDTH=%0d HEIGHT=%0d PAIR_EDGE=%0d",WIDTH,HEIGHT,PAIR_EDGE);
        $finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
