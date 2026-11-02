`timescale 1ns/1ps
`default_nettype none
// CYCLES counts sampled-clock stages: CYCLES=1 is one register.
// The long path uses read-before-write circular RAM. RAM is never reset.
module img_delay #(parameter integer BITS=8, CYCLES=1,
    parameter BANKED_ENABLE=1'b1)(
    input wire clk, rst_n, input wire [BITS-1:0] din,
    output wire [BITS-1:0] dout
);
    generate
        if (CYCLES==0) begin:g_wire
            assign dout=din;
        end else if (CYCLES==1) begin:g_reg
            reg [BITS-1:0] q;
            always @(posedge clk) if (!rst_n) q<=0; else q<=din;
            assign dout=q;
        end else if(BANKED_ENABLE && CYCLES>2049)begin:g_banked
            // Same circular read-before-write delay. Exact-sized 2048-word
            // banks and tail avoid a deep physical RAM column per payload bit.
            localparam integer DEPTH=CYCLES-1, BANK_WORDS=2048;
            localparam integer BANKS=(DEPTH+BANK_WORDS-1)/BANK_WORDS;
            localparam integer AW=$clog2(DEPTH), CW=$clog2(CYCLES+1);
            localparam integer SW=$clog2(BANKS);
            reg [AW-1:0] ptr;
            reg [CW-1:0] fill;
            wire [SW-1:0] selected=ptr>>11;
            reg [SW-1:0] selected_q;
            wire [BITS-1:0] bank_q[0:BANKS-1];
            for(genvar b=0;b<BANKS;b=b+1)begin:bank
                localparam integer WORDS=(b==BANKS-1)?(DEPTH-b*BANK_WORDS):BANK_WORDS;
                localparam integer LOCAL_AW=(WORDS<2)?1:$clog2(WORDS);
                (* ram_style="block" *) reg [BITS-1:0] mem[0:WORDS-1];
                reg [BITS-1:0] q;
                wire [LOCAL_AW-1:0] address=ptr[10:0];
                always @(posedge clk)if(rst_n && selected==b)begin
                    q<=mem[address];
                    mem[address]<=din;
                end
                assign bank_q[b]=q;
            end
            always @(posedge clk)begin
                if(!rst_n)begin ptr<=0;fill<=0;selected_q<=0;end
                else begin
                    selected_q<=selected;
                    if(ptr==DEPTH-1)ptr<=0;else ptr<=ptr+1'b1;
                    if(fill<CYCLES)fill<=fill+1'b1;
                end
            end
            assign dout=(fill==CYCLES)?bank_q[selected_q]:{BITS{1'b0}};
        end else begin:g_ram
            localparam integer DEPTH=CYCLES-1;
            localparam integer AW=(DEPTH<2)?1:$clog2(DEPTH);
            localparam integer CW=$clog2(CYCLES+1);
            (* ram_style="block" *) reg [BITS-1:0] mem[0:DEPTH-1];
            reg [AW-1:0] ptr;
            reg [CW-1:0] fill;
            reg [BITS-1:0] q;
            always @(posedge clk) if (rst_n) begin
                q<=mem[ptr];
                mem[ptr]<=din;
            end
            always @(posedge clk) begin
                if (!rst_n) begin ptr<=0;fill<=0;end
                else begin
                    if (ptr==DEPTH-1) ptr<=0;else ptr<=ptr+1'b1;
                    if (fill<CYCLES) fill<=fill+1'b1;
                end
            end
            assign dout=(fill==CYCLES)?q:{BITS{1'b0}};
        end
    endgenerate
endmodule

`default_nettype wire
