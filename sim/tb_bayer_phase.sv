`timescale 1ns/1ps
// Independent mosaics + bilinear reference for all four first-pixel phases.
// The existing spatial offset and five-clock sync delay are held unchanged.
module tb_bayer_phase;
    localparam W=32,H=10,HT=22;
    reg clk=0,rst=0,vs=0,hs=0,de=0;
    always #5 clk=~clk;
    reg [15:0] raw=0;
    reg [1:0] requested=0;
    wire [1:0] active;
    wire ov,oh,od,valid;wire [47:0] rgb;
    integer source_phase=0,pattern=0,fr=0,fg=0,fb=0;
    integer ox=0,oy=0,checked=0,fields=0,midframe_checks=0,mismatch_pixels=0;
    reg pd=0,pv=0,check_color=1,change_midframe=0;
    reg [23:0] c0,c1;reg [47:0] expected;
    reg [4:0] ds=0,hsd=0,vsd=0;
    debayer_top_2to1 dut(.in_pclk(clk),.in_rstn(rst),
        .raw_vs_i(vs),.raw_hs_i(hs),.raw_de_i(de),.raw_valid_i(de),.raw_datax4_i(raw),
        .r_gain(16'h100),.g_gain(16'h100),.b_gain(16'h100),
        .bayer_phase(requested),.bayer_active(active),
        .rgb_vs_o(ov),.rgb_hs_o(oh),.rgb_de_o(od),.rgb_valid_o(valid),.rgb_datax2_o(rgb));
    // 0=R, 1=G, 2=B. Explicit tables deliberately avoid the RTL parity XOR.
    function integer color_at(input integer x,input integer y);
        integer pos;
        begin
            pos=(y%2)*2+x%2;
            case(source_phase)
                0:case(pos)0:color_at=1;1:color_at=0;2:color_at=2;3:color_at=1;endcase
                1:case(pos)0:color_at=0;1:color_at=1;2:color_at=1;3:color_at=2;endcase
                2:case(pos)0:color_at=2;1:color_at=1;2:color_at=1;3:color_at=0;endcase
                3:case(pos)0:color_at=1;1:color_at=2;2:color_at=0;3:color_at=1;endcase
            endcase
        end
    endfunction
    function [23:0] image_rgb(input integer x,input integer y);
        integer band;reg [7:0] r,g,b;
        begin
            band=x/4;r=fr;g=fg;b=fb;
            case(pattern)
                1:begin r=(band&1)?220:16;g=(band&2)?180:32;b=(band&4)?200:8;end
                2:begin r=((x/2+y/2)%2)?220:20;g=r;b=r;end
                3:begin r=x*5+y*3;g=x*2+y*7+11;b=x*3+y*9+29;end
                4:begin r=x%2?255:0;g=y%2?0:255;b=(x+y)%2?192:64;end
                5:begin r=x<W/2?24:192;g=y<5?16:200;b=x+y<W/2?140:64;end
            endcase
            image_rgb={r,g,b};
        end
    endfunction
    function integer mosaic(input integer x,input integer y);
        reg [23:0] c;
        begin
            c=image_rgb(x,y);
            case(color_at(x,y))0:mosaic=c[23:16];1:mosaic=c[15:8];2:mosaic=c[7:0];endcase
        end
    endfunction
    function [23:0] bilinear(input integer x,input integer y);
        integer r,g,b,h,v,d,c;
        begin
            h=(mosaic(x-1,y)+mosaic(x+1,y))/2;
            v=(mosaic(x,y-1)+mosaic(x,y+1))/2;
            d=(mosaic(x-1,y-1)+mosaic(x+1,y-1)+mosaic(x-1,y+1)+mosaic(x+1,y+1))/4;
            c=(mosaic(x-1,y)+mosaic(x+1,y)+mosaic(x,y-1)+mosaic(x,y+1))/4;
            case(color_at(x,y))
                0:begin r=mosaic(x,y);g=c;b=d;end
                2:begin r=d;g=c;b=mosaic(x,y);end
                1:begin
                    g=mosaic(x,y);
                    if(color_at(x-1,y)==0)begin r=h;b=v;end
                    else begin r=v;b=h;end
                end
            endcase
            bilinear={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    always @(posedge clk)begin
        if(!rst)begin ds=0;hsd=0;vsd=0;end
        else begin
            ds={ds[3:0],de};hsd={hsd[3:0],hs};vsd={vsd[3:0],vs};
            #1;
            if({od,oh,ov,valid}!=={ds[4],hsd[4],vsd[4],ds[4]})$fatal(1,"phase change altered sync latency");
        end
    end
    always @(negedge clk)if(rst)begin
        if(ov && !pv)begin ox=0;oy=0;end
        else begin
            if(od)begin
                if(oy>=3 && oy<H-1 && ox>=4 && ox<W/2-2)begin
                    c0=bilinear(2*(ox-1),oy-1);c1=bilinear(2*(ox-1)+1,oy-1);
                    expected={c1[7:0],c1[15:8],c1[23:16],c0[7:0],c0[15:8],c0[23:16]};
                    if(check_color)begin
                        if(rgb!==expected)$fatal(1,"phase=%0d pattern=%0d x=%0d y=%0d got=%h expected=%h",source_phase,pattern,ox,oy,rgb,expected);
                        if(active!==source_phase[1:0])$fatal(1,"phase changed during active frame");
                        checked=checked+1;
                        if(change_midframe)midframe_checks=midframe_checks+1;
                    end else if(rgb!==expected)mismatch_pixels=mismatch_pixels+1;
                end
                ox=ox+1;
            end else ox=0;
            if(pd&&!od)oy=oy+1;
        end
        pd=od;pv=ov;
    end
    task field(input integer r,input integer g,input integer b);
        integer y,x;reg [7:0] lo,hi;
        begin
            @(posedge clk);#2;fr=r;fg=g;fb=b;fields=fields+1;
            for(y=0;y<H+4;y=y+1)for(x=0;x<HT;x=x+1)begin
                vs=y==0;hs=x==0;de=y>=2 && y<H+2 && x<W/2;
                lo=mosaic(2*x,y-2);hi=mosaic(2*x+1,y-2);raw={hi,lo};
                if(change_midframe && y==5 && x==4)requested=(source_phase+1)%4;
                @(posedge clk);#2;
            end
            de=0;vs=0;hs=0;
        end
    endtask
    integer p,s;
    initial begin
        repeat(4)@(posedge clk);#2;rst=1;
        // Reproduce the failure class: correct texture does not prove CFA phase.
        source_phase=1;requested=0;check_color=0;field(255,0,0);
        if(mismatch_pixels==0)$fatal(1,"wrong-phase sensitivity test failed");
        $display("C1 phase assumption reproduction: RGGB red decoded as GRBG differs at %0d interior pixel pairs",mismatch_pixels);
        check_color=1;
        for(s=0;s<4;s=s+1)begin
            source_phase=s;requested=s;pattern=0;
            field(255,0,0);field(0,255,0);field(0,0,255);field(64,128,192);field(244,106,196);
            for(p=0;p<256;p=p+1)field(p,p,p);
            for(pattern=1;pattern<=5;pattern=pattern+1)field(0,0,0);
            pattern=3;change_midframe=1;requested=s;field(0,0,0);change_midframe=0;
        end
        // Every requested phase is applied only at the next VS, even if changing
        // both bits. This also covers wrap 3->0 and all 16 phase transitions.
        pattern=0;
        for(s=0;s<4;s=s+1)for(p=0;p<4;p=p+1)begin
            source_phase=s;requested=s;field(128,128,128);
            source_phase=p;requested=p;field(128,128,128);
        end
        if(checked<64000 || midframe_checks<200)$fatal(1,"insufficient phase coverage");
        $display("BAYER PHASE PASS %0d fields, %0d interior pixel pairs, four phases, RGB/256 neutral levels/spatial patterns, mid-frame hold and all phase transitions; sync unchanged",fields,checked);$finish;
    end
    initial begin #10000000;$fatal(1,"Bayer phase timeout");end
endmodule
