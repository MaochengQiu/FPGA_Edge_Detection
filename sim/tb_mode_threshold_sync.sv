`timescale 1ns/1ps
// Integrated controller/kernel/final-HUD timing invariant. Sweep every 11-bit
// threshold while repeatedly visiting every page/preprocess, including black
// RGB and all-black binary results. Configuration cannot gate HDMI timing.
module tb_mode_threshold_sync;
    localparam W=16,H=8,HT=22,VT=14,L=5*HT+61;
    reg clk=0,rst=0;always #5 clk=~clk;
    integer x=0,y=0,frame=0;
    wire de=x<W && y>=3 && y<H+3,hs=x==W+2,vs=y<2;
    wire [23:0] rgb=(frame%8==0)?24'd0:{x[7:0],y[7:0],frame[7:0]};
    reg wr=0;reg [1:0] addr=0;reg [10:0] data=0;
    wire [10:0] threshold,pending;wire [1:0] pre;wire [2:0] mode;
    wire freeze,sof;wire [7:0] keys;wire [1:0] last,sel;wire [9:0] gr,gg,gb;
    wire [23:0] prgb,orgb;wire pde,phs,pvs,ode,ohs,ovs;
    img_control #(.DEBOUNCE_CYCLES(3),.LONG_CYCLES(20)) ctl(
        .clk(clk),.rst_n(rst),.keys_n(3'b111),.frame_sof(sof),.cfg_wr(wr),.cfg_addr(addr),.cfg_data(data),
        .threshold(threshold),.preprocess(pre),.display(mode),.freeze(freeze),.pending_threshold(pending),
        .key_press_count(keys),.last_key(last),.wb_r(gr),.wb_g(gg),.wb_b(gb),.wb_selected(sel));
    img_pipeline #(.WIDTH(W),.HEIGHT(H),.HTOTAL(HT),.NMS_ENABLE(1),.LINK_ENABLE(1)) pipe(
        .clk(clk),.rst_n(rst),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .cfg_preprocess(pre),.cfg_threshold(threshold),.cfg_display(mode),
        .out_rgb(prgb),.out_de(pde),.out_hs(phs),.out_vs(pvs),.input_sof(sof));
    edge_final_hud #(.WIDTH(W),.HEIGHT(H)) hud(
        .clk(clk),.rst_n(rst),.in_rgb(prgb),.in_de(pde),.in_hs(phs),.in_vs(pvs),
        .mean_raw_r(8'd0),.mean_raw_g(8'd0),.mean_raw_b(8'd0),
        .mean_bal_r(8'd0),.mean_bal_g(8'd0),.mean_bal_b(8'd0),
        .last_samples(9'd0),.sample_valid(1'b0),.wb_r(gr),.wb_g(gg),.wb_b(gb),.wb_selected(sel),
        .clipped_r(9'd0),.clipped_g(9'd0),.clipped_b(9'd0),
        .bayer_phase(2'd1),
        .threshold(pending),.display_mode(mode),.key_press_count(keys),
        .cam_bcd(8'h30),.done_bcd(8'h30),.selected_bcd(8'h30),
        .reject_flag(1'b0),.late_flag(1'b0),.overflow_flag(1'b0),.freeze_active(freeze),
        .underflow_flag(1'b0),.read_error_flag(1'b0),
        .out_rgb(orgb),.out_de(ode),.out_hs(ohs),.out_vs(ovs));
    reg [L-1:0] ed=0,eh=0,ev=0;
    integer checked=0;
    always @(posedge clk) begin
        if(!rst)begin ed<=0;eh<=0;ev<=0;end
        else begin
            ed<={ed[L-2:0],de};eh<={eh[L-2:0],hs};ev<={ev[L-2:0],vs};
            #1;
            if(threshold<4 || threshold>128 || pending<4 || pending>128)
                $fatal(1,"threshold outside board limits");
            if({ode,ohs,ovs}!={ed[L-1],eh[L-1],ev[L-1]})
                $fatal(1,"sync changed mode=%0d threshold=%0d frame=%0d",mode,threshold,frame);
            checked=checked+1;
        end
    end
    always @(negedge clk)if(rst)begin
        if(x==HT-1)begin x=0;if(y==VT-1)begin y=0;frame=frame+1;end else y=y+1;end
        else x=x+1;
        wr=0;
        if(y==0)case(x)
            1:begin wr=1;addr=0;data=frame%2048;end
            2:begin wr=1;addr=2;data=(frame/3)%7;end
            3:begin wr=1;addr=1;data=(frame/64)%4;end
        endcase
    end
    initial begin
        repeat(5)@(negedge clk);#1;rst=1;
        wait(frame==2050);repeat(L+2)@(negedge clk);
        if(checked<2048*HT*VT)$fatal(1,"short sweep");
        $display("MODE/THRESHOLD PASS all 2048 config inputs clamped 4..128, 7 pages, 4 preprocesses, uninterrupted DE/HS/VS");$finish;
    end
    initial begin #10000000;$fatal(1,"mode sweep timeout");end
endmodule
