`timescale 1ns/1ps
module tb_async_fifo;
    reg wc=0,rc=0;always #7 wc=~wc;always #11 rc=~rc;
    reg wrn=0,rrn=0;reg wv=0,ready=0;reg [31:0] wd=0;
    wire wready,valid;wire [31:0] data;
    img_async_fifo #(.BITS(32),.DEPTH(16)) dut(.wr_clk(wc),.wr_rst_n(wrn),
        .wr_valid(wv),.wr_ready(wready),.wr_data(wd),.rd_clk(rc),.rd_rst_n(rrn),
        .rd_valid(valid),.rd_ready(ready),.rd_data(data));
    integer produced=0,consumed=0,tickw=0,tickr=0;reg stalled=0;reg [31:0] held=0;
    always @(negedge wc) if(wrn) begin wv=produced<2000 && tickw%5!=0;wd=produced;tickw=tickw+1;end
    always @(posedge wc) if(wrn && wv && wready) produced=produced+1;
    always @(negedge rc) if(rrn) begin ready=tickr%7!=0 && tickr%7!=1;tickr=tickr+1;end
    always @(posedge rc) if(rrn) begin
        if(stalled && (!valid || data!=held)) $fatal(1,"payload changed while stalled");
        stalled=valid && !ready;held=data;
        if(valid && ready) begin
            if(data!==consumed) $fatal(1,"FIFO %0d got %0d",consumed,data);
            consumed=consumed+1;
            if(consumed==2000) begin $display("ASYNC FIFO PASS 2000 ordered words with stalls/wrap");$finish;end
        end
    end
    initial begin repeat(5) @(negedge wc);wrn=1;rrn=1;end
    initial begin #1000000;$fatal(1,"FIFO timeout");end
endmodule
