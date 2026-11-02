`timescale 1ns/1ps
`default_nettype none
// Active-low asynchronous switch, two synchronizer FFs, symmetric debounce.
module img_key_debounce #(parameter integer STABLE_CYCLES=2227500)(
    input wire clk,rst_n,key_n,output reg down,output reg press,release_event
);
    localparam integer CW=(STABLE_CYCLES<2)?1:$clog2(STABLE_CYCLES+1);
    (* async_reg="true" *) reg [1:0] sync_q;
    reg [CW-1:0] count;
    wire sample=~sync_q[1];
    always @(posedge clk) begin
        if (!rst_n) begin sync_q<=2'b11;down<=0;press<=0;release_event<=0;count<=0;end
        else begin
            sync_q<={sync_q[0],key_n};press<=0;release_event<=0;
            if (sample==down) count<=0;
            else if (count==STABLE_CYCLES-1) begin
                count<=0;down<=sample;press<=sample;release_event<=~sample;
            end else count<=count+1'b1;
        end
    end
endmodule

`default_nettype wire
