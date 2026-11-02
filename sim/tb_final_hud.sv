`timescale 1ns/1ps
module tb_final_hud;
    parameter NMS_ENABLE=1;
    parameter LINK_ENABLE=1;
    parameter WEAK_CHAIN_ENABLE=0;
    parameter TEST_PATTERN=0;
    parameter PALETTE_PROBE=0;
    parameter DVI_TRANSPORT=0;
    parameter QUALITY_FILTER=0;
    parameter RESOURCE_OPT=0;
    reg [1:0] pre=0;
    reg uf=0,rd=0,rj=0,lt=0,of=0,frz=0;
    reg [1:0] last_key=3;
    reg [7:0] expected_heartbeat=0;
    reg clk=0,rst_n=0,de=0,hs=0,vs=0;
    always #5 clk=~clk;
    reg [23:0] rgb=24'h315579;
    reg [2:0] mode=3'd3;
    reg [1:0] wb_selected=2'd1;
    reg [1:0] phase=2'd1;
    reg [10:0] threshold=40;
    wire [23:0] out_rgb;
    wire out_de,out_hs,out_vs;
    integer xx,yy,white_seen=0,cyan_seen=0,background_seen=0,bypass_seen=0;
    integer binary_text=0,binary_black=0;
    integer max_ink=0,t;
    integer c1_row_ink=0;
    integer reference_pixels=0,phase_letters=0;
    reg [11:0] expected_bcd;
    edge_final_hud #(.WIDTH(1920),.HEIGHT(1080),.NMS_ENABLE(NMS_ENABLE),.LINK_ENABLE(LINK_ENABLE),.WEAK_CHAIN_ENABLE(WEAK_CHAIN_ENABLE),.TEST_PATTERN(TEST_PATTERN),.PALETTE_PROBE(PALETTE_PROBE),.DVI_TRANSPORT(DVI_TRANSPORT),.QUALITY_FILTER(QUALITY_FILTER),.RESOURCE_OPT(RESOURCE_OPT)) dut (
        .clk(clk),.rst_n(rst_n),.in_de(de),.in_hs(hs),.in_vs(vs),.in_rgb(rgb),
        .mean_raw_r(8'hF4),.mean_raw_g(8'h6A),.mean_raw_b(8'hC4),
        .mean_bal_r(8'hB7),.mean_bal_g(8'hB9),.mean_bal_b(8'hB8),
        .last_samples(9'd256),.sample_valid(1'b1),
        .clipped_r(9'd16),.clipped_g(9'd256),.clipped_b(9'd1),
        .wb_r(10'h240),.wb_g(10'h180),.wb_b(10'h240),.wb_selected(wb_selected),
        .bayer_phase(phase),
        .threshold(threshold),.display_mode(mode),.key_press_count(8'h07),
        .last_key(last_key),
        .preprocess_mode(pre),
        .cam_bcd(8'h30),.done_bcd(8'h30),.selected_bcd(8'h30),
        .reject_flag(rj),.late_flag(lt),.overflow_flag(of),
        .freeze_active(frz),.underflow_flag(uf),.read_error_flag(rd),
        .out_rgb(out_rgb),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs));
    task run_rows;
      integer y,x;
      begin
        @(negedge clk); de=0;vs=1;
        repeat(3)@(negedge clk); vs=0;
        expected_heartbeat=expected_heartbeat+1'b1;
        if(dut.frame_heartbeat!==expected_heartbeat)$fatal(1,"frame heartbeat did not advance");
        for(y=0;y<120;y=y+1)begin
          de=1;
          for(x=0;x<1920;x=x+1)begin
             @(negedge clk);
             if(!out_de) $fatal(1,"DE sync lost");
             if(dut.area && ((mode==6 && dut.row==1 && dut.col==54) ||
                            (mode!=6 && dut.row==0 && dut.col==44)))
                 if(dut.letter!==dut.hex_ascii({2'd0,pre}))$fatal(1,"PRE indicator mismatch");
             if(mode!=6 && dut.area && dut.row==1)case(dut.col)
                 17:if(dut.letter!==8'h30+uf)$fatal(1,"U flag");
                 21:if(dut.letter!==8'h30+rd)$fatal(1,"D flag");
                 25:if(dut.letter!==8'h30+rj)$fatal(1,"R flag");
                 29:if(dut.letter!==8'h30+lt)$fatal(1,"L flag");
                 33:if(dut.letter!==8'h30+of)$fatal(1,"O flag");
                 37:if(dut.letter!==8'h30+frz)$fatal(1,"freeze flag");
                 49:if(dut.letter!==8'h30+last_key)$fatal(1,"last button");
             endcase
             if(mode==3'd2)begin
                 if(out_rgb==24'hffffff)binary_text=binary_text+1;
                 if(out_rgb==24'd0)binary_black=binary_black+1;
                 if(out_rgb==24'hffcc40)max_ink=max_ink+1;
                 if(!((x>=16 && x<752 && y>=12 && y<30)||(x>=16 && x<912 && y>=30 && y<48)) && out_rgb!==24'd0)
                     $fatal(1,"binary label escaped its rectangle x%0d y%0d",x,y);
             end else if(mode!=3'd6)begin
                 if(!((x>=16 && x<752 && y>=12 && y<30)||(x>=16 && x<912 && y>=30 && y<48)))begin
                     if(out_rgb!==rgb)$fatal(1,"compact HUD escaped bounds mode %0d x%0d y%0d",mode,x,y);
                     bypass_seen=bypass_seen+1;
                 end
             end else begin
                 if(dut.area && dut.row==0 && dut.col<4)begin
                     case(dut.col)
                         0:if(dut.letter!==8'h45)$fatal(1,"E1 marker E");
                         1:if(dut.letter!==(RESOURCE_OPT?8'h47:(QUALITY_FILTER?8'h37:(DVI_TRANSPORT?8'h36:(PALETTE_PROBE?8'h35:8'h34)))))$fatal(1,"version marker");
                         2:if(dut.letter!==(RESOURCE_OPT?8'h52:(QUALITY_FILTER?8'h51:(DVI_TRANSPORT?8'h44:(PALETTE_PROBE?8'h41:(TEST_PATTERN?8'h54:8'h44))))))$fatal(1,"probe marker");
                         3:if(dut.letter!==8'h20)$fatal(1,"E1 marker space");
                     endcase
                 end
                 if(y==100 && x>=32 && x<336 && x%64==32)begin
                     case(x/64)
                         0:if(out_rgb!==24'hff0000)$fatal(1,"red reference");
                         1:if(out_rgb!==24'h00ff00)$fatal(1,"green reference");
                         2:if(out_rgb!==24'h0000ff)$fatal(1,"blue reference");
                         3:if(out_rgb!==24'hffffff)$fatal(1,"white reference");
                         4:if(out_rgb!==24'h000000)$fatal(1,"black reference");
                     endcase
                     reference_pixels=reference_pixels+1;
                 end
                 if(dut.row==3 && dut.col>=40 && dut.col<=43 && dut.area)begin
                     if(dut.letter!==dut.phase_ascii(phase,dut.col-40))$fatal(1,"phase name glyph");
                     phase_letters=phase_letters+1;
                 end
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
       mode=3'd3;run_rows();
       mode=3'd0;run_rows();
       mode=3'd3;
       for(t=0;t<4;t=t+1)begin pre=t;uf=t[0];rd=t[1];rj=t[0];lt=t[1];of=t[0];frz=t[1];last_key=t;run_rows();end
       mode=3'd6;wb_selected=3;
       for(t=0;t<4;t=t+1)begin phase=t;pre=t;run_rows();end
       rgb=0;mode=3'd2;run_rows();
       threshold=128;run_rows();
       mode=3'd7;rgb=24'he0f0ff;run_rows();
       if(white_seen<100||cyan_seen<100||background_seen<10000||bypass_seen<200000)
         $fatal(1,"V8 visibility count text=%0d stripe=%0d background=%0d clean=%0d",white_seen,cyan_seen,background_seen,bypass_seen);
       if(binary_text<100 || binary_black<100000 || max_ink<100)$fatal(1,"binary black/limit label invisible");
       if(c1_row_ink<100)$fatal(1,"C1 clipping telemetry invisible");
       if(reference_pixels!=20 || phase_letters<100)$fatal(1,"C2 reference/phase coverage");
       $display("V10-E4 HUD PASS TEST=%0d flags/heartbeat/PRE, decimal4..128, black M2 still has independent HUD",TEST_PATTERN);
       $finish;
    end
    initial begin #60000000;$fatal(1,"timeout");end
endmodule
