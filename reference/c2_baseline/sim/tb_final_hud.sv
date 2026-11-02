`timescale 1ns/1ps
module tb_final_hud;
    reg clk=0,rst_n=0,de=0,hs=0,vs=0;
    always #5 clk=~clk;
    reg [23:0] rgb=24'h315579;
    reg [2:0] mode=3'd3;
    reg [1:0] wb_selected=2'd1;
    reg [10:0] threshold=40;
    wire [23:0] out_rgb;
    wire out_de,out_hs,out_vs;
    integer xx,yy,white_seen=0,cyan_seen=0,background_seen=0,bypass_seen=0;
    integer binary_text=0,binary_black=0;
    integer max_ink=0,t;
    integer c1_row_ink=0;
    reg [11:0] expected_bcd;
    edge_final_hud #(.WIDTH(1920),.HEIGHT(1080)) dut (
        .clk(clk),.rst_n(rst_n),.in_de(de),.in_hs(hs),.in_vs(vs),.in_rgb(rgb),
        .mean_raw_r(8'hF4),.mean_raw_g(8'h6A),.mean_raw_b(8'hC4),
        .mean_bal_r(8'hB7),.mean_bal_g(8'hB9),.mean_bal_b(8'hB8),
        .last_samples(9'd256),.sample_valid(1'b1),
        .clipped_r(9'd16),.clipped_g(9'd256),.clipped_b(9'd1),
        .wb_r(10'h0c0),.wb_g(10'h1c0),.wb_b(10'h0f0),.wb_selected(wb_selected),
        .threshold(threshold),.display_mode(mode),.key_press_count(8'h07),
        .cam_bcd(8'h30),.done_bcd(8'h30),.selected_bcd(8'h30),
        .reject_flag(1'b0),.late_flag(1'b0),.overflow_flag(1'b0),
        .freeze_active(1'b0),.underflow_flag(1'b0),.read_error_flag(1'b0),
        .out_rgb(out_rgb),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs));
    task run_rows;
      integer y,x;
      begin
        @(negedge clk); de=0;vs=1;
        repeat(3)@(negedge clk); vs=0;
        for(y=0;y<90;y=y+1)begin
          de=1;
          for(x=0;x<1920;x=x+1)begin
             @(negedge clk);
             if(!out_de) $fatal(1,"DE sync lost");
             if(mode==3'd2)begin
                 if(out_rgb==24'hffffff)binary_text=binary_text+1;
                 if(out_rgb==24'd0)binary_black=binary_black+1;
                 if(out_rgb==24'hffcc40)max_ink=max_ink+1;
                 if((x<16 || x>=544 || y<12 || y>=30) && out_rgb!==24'd0)
                     $fatal(1,"binary label escaped its rectangle x%0d y%0d",x,y);
             end else if(mode!=3'd6)begin
                 if(x<16 || x>=544 || y<12 || y>=30)begin
                     if(out_rgb!==rgb)$fatal(1,"compact HUD escaped bounds mode %0d x%0d y%0d",mode,x,y);
                     bypass_seen=bypass_seen+1;
                 end
             end else begin
                 if(out_rgb==24'hffffff)white_seen=white_seen+1;
                 if(out_rgb==24'hffffff && y>=66 && y<84)c1_row_ink=c1_row_ink+1;
                 if(out_rgb==24'h00ffff)cyan_seen=cyan_seen+1;
                 if(out_rgb==rgb)background_seen=background_seen+1;
             end
          end
          de=0;hs=1;repeat(6)@(negedge clk);hs=0;repeat(6)@(negedge clk);
        end
      end
    endtask
    initial begin
       repeat(4)@(negedge clk);rst_n=1;
       for(t=4;t<=128;t=t+1)begin
           threshold=t;repeat(15)@(negedge clk);
           expected_bcd=((t/100)<<8)|(((t/10)%10)<<4)|(t%10);
           if(dut.threshold_bcd!==expected_bcd)$fatal(1,"decimal threshold %0d got %h",t,dut.threshold_bcd);
       end
       threshold=40;repeat(15)@(negedge clk);
       @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;
       mode=3'd3;run_rows();
       mode=3'd0;run_rows();
       mode=3'd6;run_rows();
       rgb=0;mode=3'd2;run_rows();
       threshold=128;run_rows();
       if(white_seen<100||cyan_seen<100||background_seen<10000||bypass_seen<200000)
         $fatal(1,"V8 visibility count text=%0d stripe=%0d background=%0d clean=%0d",white_seen,cyan_seen,background_seen,bypass_seen);
       if(binary_text<100 || binary_black<100000 || max_ink<100)$fatal(1,"binary black/limit label invisible");
       if(c1_row_ink<100)$fatal(1,"C1 clipping telemetry invisible");
       $display("V10-C1 HUD PASS text=%0d stripe=%0d untouched=%0d MAX-ink=%0d clip-row=%0d decimal 4..128",white_seen,cyan_seen,bypass_seen,max_ink,c1_row_ink);
       $finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
