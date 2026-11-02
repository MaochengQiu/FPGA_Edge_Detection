`timescale 1ns/1ps
`default_nettype none
// Exact connectivity on a DIRECTION-CONSTRAINED graph inside a centered 5x5
// patch, not global hysteresis. Edges cannot jump by 90 degrees in normal
// direction or travel along either endpoint's exact gradient normal.
// Descriptor={normal[1:0], high-NMS seed, low-NMS candidate, raw>=low}.
// Low is ceil(high/2), formed upstream on the original pixel/frame token.
// Default: >=3 connected candidate pixels, >=3 high seeds. Reject single
// strong speckles and two-pixel components; grow only supported weak paths.
// A raw-supported single missing NMS point may bridge an opposite pair along
// the edge tangent, with exact matching normal bins. No blind closing/dilation.
// II=1. ctl and output center latency = 2*HTOTAL+32 clocks.
module img_edge_link #(parameter integer WIDTH=1920,HEIGHT=1080,HTOTAL=2200,
    MIN_COMPONENT=3,MIN_SEEDS=3,parameter BRIDGE_ENABLE=1'b1,
    parameter WEAK_CHAIN_ENABLE=1'b0)(
    input wire clk,rst_n,input wire [4:0] descriptor,input wire [3:0] ctl,
    output reg edge_pixel,output wire [3:0] out_ctl
);
    localparam integer STEPS=24,LATENCY=2*HTOTAL+32;
    wire [124:0] win;wire wvalid;
    wire [4:0] p[0:24];
    genvar i;
    generate for(i=0;i<25;i=i+1)begin:unpack
        assign p[i]=win[5*i+:5];
    end endgenerate
    img_window5x5 #(.BITS(5),.WIDTH(WIDTH),.HEIGHT(HEIGHT)) patch(
        .clk(clk),.rst_n(rst_n),.de(ctl[0]),.vs(ctl[2]),.pixel(descriptor),.window(win),.window_valid(wvalid));
    img_delay #(.BITS(4),.CYCLES(LATENCY)) timing(.clk(clk),.rst_n(rst_n),.din(ctl),.dout(out_ctl));
    function pair_ok(input [4:0] center,a,b,input [1:0] normal);
        begin pair_ok=center[0] && !center[1] && a[1] && b[1] &&
            center[4:3]==normal && a[4:3]==normal && b[4:3]==normal;end
    endfunction
    wire [24:0] candidates,seeds;
    // E3 supplement: five ORIGINAL NMS candidates on a straight tangent,
    // exact same normal bin, supported by >=1 original high-NMS seed.
    // Does not recruit bridges, isolated pairs, or all-weak chains.
    function straight5(input [4:0] a,b,c,d,e,input [1:0] normal);
        begin
            straight5=a[1] && b[1] && c[1] && d[1] && e[1] &&
                a[4:3]==normal && b[4:3]==normal && c[4:3]==normal &&
                d[4:3]==normal && e[4:3]==normal &&
                (a[2] || b[2] || c[2] || d[2] || e[2]);
        end
    endfunction
    wire weak_chain=WEAK_CHAIN_ENABLE && (
        straight5(p[10],p[11],p[12],p[13],p[14],2'd2) ||
        straight5(p[2],p[7],p[12],p[17],p[22],2'd0) ||
        straight5(p[0],p[6],p[12],p[18],p[24],2'd3) ||
        straight5(p[4],p[8],p[12],p[16],p[20],2'd1));
    generate for(i=0;i<25;i=i+1)begin:graph
        if(i/5>=1 && i/5<=3 && i%5>=1 && i%5<=3)begin:interior
            wire bridge=BRIDGE_ENABLE && (
                pair_ok(p[i],p[i-1],p[i+1],2'd2) || pair_ok(p[i],p[i-5],p[i+5],2'd0) ||
                pair_ok(p[i],p[i-6],p[i+6],2'd3) || pair_ok(p[i],p[i-4],p[i+4],2'd1));
            assign candidates[i]=p[i][1] || bridge;
        end else begin:rim
            assign candidates[i]=p[i][1];
        end
        assign seeds[i]=p[i][2] && p[i][1];
    end endgenerate
    function compatible(input [4:0] a,b,input ca,cb,input [1:0] normal);
        reg [1:0] delta;
        begin
            delta=a[4:3]-b[4:3];
            compatible=ca && cb && delta!=2'd2 && a[4:3]!=normal && b[4:3]!=normal;
        end
    endfunction
    // Four undirected links per node: E, S, SE, SW. Boundary links are zero.
    // Only 72 of the 100 static bits are real links. Precompute once, then
    // pipeline the adjacency graph instead of repeating angle tests 24 times.
    wire [99:0] adjacency;
    generate for(i=0;i<25;i=i+1)begin:adj
        if(i%5<4)assign adjacency[4*i]=compatible(p[i],p[i+1],candidates[i],candidates[i+1],2'd0);
        else assign adjacency[4*i]=1'b0;
        if(i/5<4)assign adjacency[4*i+1]=compatible(p[i],p[i+5],candidates[i],candidates[i+5],2'd2);
        else assign adjacency[4*i+1]=1'b0;
        if(i/5<4 && i%5<4)assign adjacency[4*i+2]=compatible(p[i],p[i+6],candidates[i],candidates[i+6],2'd1);
        else assign adjacency[4*i+2]=1'b0;
        if(i/5<4 && i%5>0)assign adjacency[4*i+3]=compatible(p[i],p[i+4],candidates[i],candidates[i+4],2'd3);
        else assign adjacency[4*i+3]=1'b0;
    end endgenerate
    reg [99:0] links[0:STEPS];
    reg [24:0] highs[0:STEPS],reach[0:STEPS];
    reg [STEPS:0] good;
    reg [STEPS:0] chain;
    always @(posedge clk)begin
        if(!rst_n)begin links[0]<=0;highs[0]<=0;reach[0]<=0;good[0]<=0;chain[0]<=0;end
        else begin
            links[0]<=adjacency;highs[0]<=seeds;
            reach[0]<=candidates[12]?25'h0001000:25'd0;
            good[0]<=wvalid;
            chain[0]<=weak_chain;
        end
    end
    genvar j;
    generate for(i=0;i<STEPS;i=i+1)begin:trace
        wire [24:0] expanded;
        for(j=0;j<25;j=j+1)begin:vertex
            wire [7:0] incoming;
            if(j%5<4)assign incoming[0]=reach[i][j+1] && links[i][4*j];else assign incoming[0]=0;
            if(j%5>0)assign incoming[1]=reach[i][j-1] && links[i][4*(j-1)];else assign incoming[1]=0;
            if(j/5<4)assign incoming[2]=reach[i][j+5] && links[i][4*j+1];else assign incoming[2]=0;
            if(j/5>0)assign incoming[3]=reach[i][j-5] && links[i][4*(j-5)+1];else assign incoming[3]=0;
            if(j/5<4 && j%5<4)assign incoming[4]=reach[i][j+6] && links[i][4*j+2];else assign incoming[4]=0;
            if(j/5>0 && j%5>0)assign incoming[5]=reach[i][j-6] && links[i][4*(j-6)+2];else assign incoming[5]=0;
            if(j/5<4 && j%5>0)assign incoming[6]=reach[i][j+4] && links[i][4*j+3];else assign incoming[6]=0;
            if(j/5>0 && j%5<4)assign incoming[7]=reach[i][j-4] && links[i][4*(j-4)+3];else assign incoming[7]=0;
            assign expanded[j]=reach[i][j] || (|incoming);
        end
        always @(posedge clk)begin
            if(!rst_n)begin links[i+1]<=0;highs[i+1]<=0;reach[i+1]<=0;good[i+1]<=0;chain[i+1]<=0;end
            else begin
                links[i+1]<=links[i];highs[i+1]<=highs[i];good[i+1]<=good[i];
                reach[i+1]<=expanded;
                chain[i+1]<=chain[i];
            end
        end
    end endgenerate
    function [2:0] count5(input [4:0] a);
        begin count5={2'd0,a[0]}+{2'd0,a[1]}+{2'd0,a[2]}+{2'd0,a[3]}+{2'd0,a[4]};end
    endfunction
    reg [2:0] component_rows[0:4],seed_rows[0:4];
    reg [4:0] component_count,seed_count;reg good_a,good_b;
    reg chain_a,chain_b;
    integer row;
    always @(posedge clk)begin
        if(!rst_n)begin
            for(row=0;row<5;row=row+1)begin component_rows[row]<=0;seed_rows[row]<=0;end
            component_count<=0;seed_count<=0;good_a<=0;good_b<=0;edge_pixel<=0;
            chain_a<=0;chain_b<=0;
        end else begin
            for(row=0;row<5;row=row+1)begin
                component_rows[row]<=count5(reach[STEPS][row*5+:5]);
                seed_rows[row]<=count5(reach[STEPS][row*5+:5] & highs[STEPS][row*5+:5]);
            end
            component_count<={2'd0,component_rows[0]}+{2'd0,component_rows[1]}+{2'd0,component_rows[2]}+{2'd0,component_rows[3]}+{2'd0,component_rows[4]};
            seed_count<={2'd0,seed_rows[0]}+{2'd0,seed_rows[1]}+{2'd0,seed_rows[2]}+{2'd0,seed_rows[3]}+{2'd0,seed_rows[4]};
            good_a<=good[STEPS];good_b<=good_a;
            chain_a<=chain[STEPS];chain_b<=chain_a;
            edge_pixel<=good_b && ((component_count>=MIN_COMPONENT && seed_count>=MIN_SEEDS) || chain_b);
        end
    end
endmodule
`default_nettype wire
