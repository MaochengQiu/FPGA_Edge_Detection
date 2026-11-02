`timescale 1ns/1ps
`default_nettype none
// KEY1/2 normally adjust Sobel threshold; on diagnostic display page (6)
// they instead adjust the chosen POST-DEBAYER RGB gain by +/- 1/32 (C1).
// KEY3 short cycles pages 0..6. KEY3 long cycles preprocess normally,
// but selects R->G->B channel on page 6. KEY1+KEY2 retains freeze chord.
// V8: white-card preset in UQ2.8. Defaults R=.75, G=1.75, B=.9375.
// User trim from 0.5x to 2.25x in full-color mode 6 only.
module img_control #(parameter integer DEBOUNCE_CYCLES=2227500,
    LONG_CYCLES=148500000,THRESHOLD_STEP=1,
    THRESHOLD_MIN=4,THRESHOLD_MAX=128,THRESHOLD_DEFAULT=24,
    REPEAT_DELAY_CYCLES=74250000,REPEAT_CYCLES=14850000,WB_STEP=8)(
    input wire clk,rst_n,input wire [2:0] keys_n,input wire frame_sof,
    input wire cfg_wr,input wire [1:0] cfg_addr,input wire [10:0] cfg_data,
    output wire [10:0] threshold,output wire [1:0] preprocess,
    output wire [2:0] display,output reg freeze,
    output wire [10:0] pending_threshold,
    output reg [7:0] key_press_count,output reg [1:0] last_key,
    output reg [9:0] wb_r,wb_g,wb_b,
    output reg [1:0] wb_selected
);
    wire [2:0] down,press,release_event;
    genvar k;
    generate for(k=0;k<3;k=k+1)begin:g_key
        img_key_debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) key_filter(
            .clk(clk),.rst_n(rst_n),.key_n(keys_n[k]),.down(down[k]),
            .press(press[k]),.release_event(release_event[k]));
    end endgenerate
    localparam integer LW=(LONG_CYCLES<2)?1:$clog2(LONG_CYCLES+1);
    reg [LW-1:0] hold_count;
    reg long_fired,chord_q;
    reg [10:0] pending_t,active_t;
    reg [1:0] pending_p,active_p;
    reg [2:0] pending_d,active_d;
    localparam [10:0] T_STEP=THRESHOLD_STEP;
    localparam [10:0] T_MIN=THRESHOLD_MIN,T_MAX=THRESHOLD_MAX,T_DEFAULT=THRESHOLD_DEFAULT;
    localparam [9:0] W_STEP=WB_STEP,W_MIN=10'h080,W_MAX=10'h240;
    localparam integer RW=$clog2(((REPEAT_DELAY_CYCLES>REPEAT_CYCLES)?REPEAT_DELAY_CYCLES:REPEAT_CYCLES)+1);
    reg [RW-1:0] repeat_count;
    reg repeating;
    wire chord=down[0]&&down[1];
    wire tuning_page=(pending_d==3'd6);
    wire threshold_held=(down[0]^down[1]) && !tuning_page;
    wire repeat_tick=threshold_held && (repeating?
        repeat_count==REPEAT_CYCLES-1:repeat_count==REPEAT_DELAY_CYCLES-1);
    wire up_event=press[0] || (repeat_tick && down[0]);
    wire down_event=press[1] || (repeat_tick && down[1]);
    // Widen BEFORE adding so saturation also works near the 11-bit limit.
    wire [11:0] next_up={1'b0,pending_t}+{1'b0,T_STEP};
    wire [11:0] lower_guard={1'b0,T_MIN}+{1'b0,T_STEP};
    always @(posedge clk)begin
        if(!rst_n)begin
            pending_t<=T_DEFAULT;active_t<=T_DEFAULT;
            pending_p<=0;active_p<=0;pending_d<=3;active_d<=3;
            freeze<=0;hold_count<=0;long_fired<=0;chord_q<=0;
            key_press_count<=0;last_key<=0;
            repeat_count<=0;repeating<=0;
            wb_r<=10'h0c0;wb_g<=10'h1c0;wb_b<=10'h0f0;wb_selected<=0;
        end else begin
            if(!threshold_held || |press[1:0]) begin repeat_count<=0;repeating<=0;end
            else if(repeat_tick) begin repeat_count<=0;repeating<=1;end
            else repeat_count<=repeat_count+1'b1;
            chord_q<=chord;
            if(|press)begin
                key_press_count<=key_press_count+1'b1;
                last_key<=press[0]?2'd1:(press[1]?2'd2:2'd3);
            end
            if(chord && !chord_q)freeze<=~freeze;
            if(up_event&&!down[1])begin
                if(tuning_page)begin
                    case(wb_selected)
                        0:wb_r<=(wb_r>=W_MAX-W_STEP)?W_MAX:wb_r+W_STEP;
                        1:wb_g<=(wb_g>=W_MAX-W_STEP)?W_MAX:wb_g+W_STEP;
                        default:wb_b<=(wb_b>=W_MAX-W_STEP)?W_MAX:wb_b+W_STEP;
                    endcase
                end else pending_t<=(next_up>={1'b0,T_MAX})?T_MAX:next_up[10:0];
            end
            if(down_event&&!down[0])begin
                if(tuning_page)begin
                    case(wb_selected)
                        0:wb_r<=(wb_r<=W_MIN+W_STEP)?W_MIN:wb_r-W_STEP;
                        1:wb_g<=(wb_g<=W_MIN+W_STEP)?W_MIN:wb_g-W_STEP;
                        default:wb_b<=(wb_b<=W_MIN+W_STEP)?W_MIN:wb_b-W_STEP;
                    endcase
                end else pending_t<=({1'b0,pending_t}<=lower_guard)?T_MIN:pending_t-T_STEP;
            end
            if(down[2])begin
                if(!long_fired)begin
                    if(hold_count==LONG_CYCLES-1)begin
                        long_fired<=1;
                        if(tuning_page)wb_selected<=(wb_selected>=2)?2'd0:wb_selected+2'd1;
                        else pending_p<=pending_p+1'b1;
                    end else hold_count<=hold_count+1'b1;
                end
            end else begin
                hold_count<=0;
                if(release_event[2])begin
                    if(!long_fired)pending_d<=(pending_d>=6)?3'd0:pending_d+3'd1;
                    long_fired<=0;
                end
            end
            if(cfg_wr)case(cfg_addr)
                0:pending_t<=(cfg_data<T_MIN)?T_MIN:((cfg_data>T_MAX)?T_MAX:cfg_data);
                1:if(cfg_data<=3)pending_p<=cfg_data[1:0];
                2:if(cfg_data<=6)pending_d<=cfg_data[2:0];
                3:freeze<=cfg_data[0];
            endcase
            if(frame_sof)begin active_t<=pending_t;active_p<=pending_p;active_d<=pending_d;end
        end
    end
    assign threshold=frame_sof?pending_t:active_t;
    assign preprocess=frame_sof?pending_p:active_p;
    assign display=frame_sof?pending_d:active_d;
    assign pending_threshold=pending_t;
endmodule
`default_nettype wire
