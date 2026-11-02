`timescale 1ns/1ps
module tb_video_out;
    localparam W=16,H=6,HT=14,VT=10,N=W*H/2;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [15:0] data=0;reg valid=0,sof=0,eol=0;
    wire ready,request,de,hs,vs,underflow;wire [15:0] pixels;
    wire [31:0] drops,shown;
    img_video_out #(.WIDTH(W),.HEIGHT(H),.HFP(4),.HSP(4),.HBP(4),.VFP(1),.VSP(2),.VBP(1)) dut(
        .clk(clk),.rst_n(rst),.in_data(data),.in_valid(valid),.in_sof(sof),.in_eol(eol),.in_ready(ready),
        .frame_request(request),.out_data(pixels),.out_de(de),.out_hs(hs),.out_vs(vs),
        .underflow_sticky(underflow),.underflow_frames(drops),.displayed_frames(shown));
    integer rh=0,rv=0,checked=0,recovered=0;
    reg expect_de;
    always @(posedge clk) begin
        if(!rst)begin rh=0;rv=0;end
        else begin
            expect_de=rh>=4 && rh<12 && rv>=3 && rv<9;
            #1;
            if({hs,vs,de}!={rh<2,rv<2,expect_de})
                $fatal(1,"raster changed h=%0d v=%0d hs/vs/de=%b%b%b",rh,rv,hs,vs,de);
            if(request!=(rh==0 && rv==0))$fatal(1,"frame request period");
            if(de && pixels>=16'h400 && pixels<16'h400+N)recovered=recovered+1;
            checked=checked+1;
            if(rh==HT-1)begin rh=0;if(rv==VT-1)rv=0;else rv=rv+1;end
            else rh=rh+1;
        end
    end
    task send_frame(input integer id,input integer fault);
        integer i;
        begin
            for(i=0;i<N;i=i+1)begin
                @(negedge clk);
                if(fault==1 && i==12)begin
                    valid=0;repeat(25)@(negedge clk);
                end
                data=id*256+i;sof=i==0;eol=i%(W/2)==W/2-1;
                if(fault==2 && i==9)eol=1;
                valid=1;
                @(posedge clk);while(!ready)@(posedge clk);
            end
            @(negedge clk);valid=0;sof=0;eol=0;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        send_frame(1,0);send_frame(2,1);send_frame(3,2);send_frame(4,0);
        repeat(HT*VT)@(negedge clk);
        if(!underflow || drops<2 || shown<2 || recovered!=N || checked<HT*VT*4)
            $fatal(1,"recovery failed drop=%0d shown=%0d recovered=%0d",drops,shown,recovered);
        $display("VIDEO OUT PASS continuous HS/VS/DE, starvation, EOL fault, SOF recovery");$finish;
    end
    initial begin #1000000;$fatal(1,"video timeout");end
endmodule
