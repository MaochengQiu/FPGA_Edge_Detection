`timescale 1ns/1ps
`default_nettype none
// Bounded single-target contour extraction. No backpressure or DDR accesses.
// OR pooling preserves thin edges. Gap jumps connect original edge samples;
// the invented connections NEVER count as observed shape evidence.
module img_geometry #(
 parameter WIDTH=1920,HEIGHT=1080,S=4,QUEUE_CAP=2048,PROCESS_BUDGET=400000
)(
 input wire clk,rst_n,edge_pixel,input wire [3:0] ctl,
 output reg [2:0] shape,output reg [15:0] left,top,right,bottom,
 output reg [((HEIGHT/2+S-1)/S)*8-1:0] row_lo,row_hi,
 output reg [3:0] debug_reason,output reg [15:0] debug_cells,debug_count,
 output reg [31:0] debug_sides,output reg [7:0] debug_radial,
 output reg [((WIDTH/2+S-1)/S)-1:0] support_top,support_bottom,
 output reg [((HEIGHT/2+S-1)/S)-1:0] support_left,support_right
);
 localparam RX=WIDTH/4,RY=HEIGHT/4,RW=WIDTH/2,RH=HEIGHT/2;
 localparam CW=(RW+S-1)/S,CH=(RH+S-1)/S,CELLS=CW*CH;
 localparam AW=($clog2(CELLS)<1)?1:$clog2(CELLS),QW=$clog2(QUEUE_CAP+1);
 localparam CAPTURE=0,SCAN_READ=1,SCAN_EVAL=2,POP_READ=3,POP_LATCH=4,
  N_ADDR=5,N_READ=6,N_EVAL=7,N_NEXT=8,COMP_DONE=9,COPY_READ=10,
  COPY_WRITE=11,NEXT_SCAN=12,CLASS_SETUP=13,CLASS_READ=14,
  CLASS_CALC=15,CLASS_DIST=16,CLASS_ACC=17,MASK_SCAN=18,DECIDE=19,DONE=20,ELLIPSE_SUM=21,ELLIPSE_READY=22;
 // Reason codes: 0 accepted; 1 warmup; 2 no edge; 3 small/clipped;
 // 4 shape mismatch; 5 ambiguous; 6 capacity; 7 deadline; 8 gap; 9 clutter.
 wire [15:0] x,y;wire unused_sof,unused_eol;
 img_coords #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) coords(.clk(clk),.rst_n(rst_n),
  .de(ctl[0]),.vs(ctl[2]),.x(x),.y(y),.sof(unused_sof),.eol(unused_eol));
 wire roi=ctl[0] && x>=RX && x<RX+RW && y>=RY && y<RY+RH;
 wire [15:0] ux=x-RX,uy=y-RY;
 wire [7:0] cx=ux/S,cy=uy/S;
 reg [CW-1:0] row_or;reg horizontal;
 wire partial=(ux%S==0)?edge_pixel:(horizontal|edge_pixel);
 wire pooled=(uy%S==0)?partial:(partial|row_or[cx]);
 wire pool_write=frame_synced && roi && (ux%S==S-1 || ux==RW-1) && (uy%S==S-1 || uy==RH-1);
 wire [AW-1:0] pool_addr=cy*CW+cx;
 (* ram_style="block" *) reg [1:0] bitmap[0:CELLS-1];
 (* ram_style="block" *) reg [15:0] work_queue[0:QUEUE_CAP-1];
 (* ram_style="block" *) reg [15:0] best_queue[0:QUEUE_CAP-1];
 reg [1:0] map_q;reg [15:0] work_q,best_q;
 reg [AW-1:0] scan_addr,naddr;
 reg [QW-1:0] head,tail,copy_index,class_index,best_count,second_count;
 reg [7:0] scan_x,scan_y,node_x,node_y;
 reg [7:0] cxl,cxr,cyt,cyb,bxl,bxr,byt,byb,sxl,sxr,syt,syb;
 reg [4:0] state;reg [4:0] neighbor;
 reg vsq,ready,frame_seen,frame_synced;reg [19:0] work_cycles;
 reg [15:0] raw_cells,components;
 reg [2:0] pending;reg [3:0] reason;
 reg [15:0] pl,pt,pr,pb,win_l,win_t,win_r,win_b;
 reg [2:0] chosen_shape,trial_shape;
 reg [QW-1:0] chosen_count;
 reg [3:0] candidates;
 reg [CH*8-1:0] trial_lo,trial_hi,win_lo,win_hi;
 reg [CW-1:0] win_tm,win_bm;reg [CH-1:0] win_lm,win_rm;
 reg [31:0] win_sides;reg [7:0] win_radial;
 reg [17:0] a2,b2;reg [19:0] xx,yy;
 reg [37:0] weighted_x,weighted_y,ellipse_value,ellipse_rhs;
 wire [8:0] band=(w<h?w:h)/8<2?2:((w<h?w:h)/8>6?6:(w<h?w:h)/8);
 wire [8:0] corner_tol=(w<h?w:h)/8<1?1:(w<h?w:h)/8;
 reg [8:0] w,h,centerx,centery,radius;
 reg [20:0] radius2,distance2;reg [17:0] interior_area;reg signed [9:0] dx,dy;
 reg [7:0] px,py;reg [15:0] band_count,inliers,envelope_count;reg profile_pass;
 reg [CW-1:0] top_mask,bottom_mask,ctop,cbottom;
 reg [CH-1:0] left_mask,right_mask,cleft,cright;
 reg [3:0] corners;reg [7:0] sectors;reg [8:0] checkindex;
 reg [7:0] nt,nb,nl,nr,ct,cb,cl,cr;
 reg [7:0] gap_t,gap_b,gap_l,gap_r,max_t,max_b,max_l,max_r;
 reg signed [9:0] nx,ny;
 always @* begin
  nx=$signed({1'b0,node_x});ny=$signed({1'b0,node_y});
  case(neighbor)
   0:nx=nx-1;1:nx=nx+1;2:ny=ny-1;3:ny=ny+1;
   4:begin nx=nx-1;ny=ny-1;end 5:begin nx=nx+1;ny=ny-1;end
   6:begin nx=nx-1;ny=ny+1;end 7:begin nx=nx+1;ny=ny+1;end
   8:nx=nx-2;9:nx=nx+2;10:ny=ny-2;11:ny=ny+2;
   12:nx=nx-3;13:nx=nx+3;14:ny=ny-3;15:ny=ny+3;
   16:nx=nx-4;17:nx=nx+4;18:ny=ny-4;19:ny=ny+4;
   20:nx=nx-5;21:nx=nx+5;22:ny=ny-5;23:ny=ny+5;
  endcase
 end
 wire neighbor_valid=nx>=0 && nx<CW && ny>=0 && ny<CH;
 wire [AW-1:0] map_read_addr=(state==N_READ || state==N_EVAL)?naddr:scan_addr;
 wire [QW-1:0] work_read_addr=(state>=CLASS_READ && state<=CLASS_ACC || state==ELLIPSE_SUM || state==ELLIPSE_READY)?class_index:head;
 reg map_we,queue_we;reg [AW-1:0] map_wa;reg [1:0] map_wd;
 reg [QW-1:0] queue_wa;reg [15:0] queue_wd;
 // Explicit mux before each physical write port. Separate indexed writes in
 // branches are treated as incompatible ports by Efinity's RAM inference.
 always @*begin
  map_we=0;map_wa=pool_addr;map_wd={1'b0,pooled};
  queue_we=0;queue_wa=0;queue_wd={scan_y,scan_x};
  if(state==CAPTURE && pool_write)map_we=1;
  else if(state==SCAN_EVAL && map_q==2'b01)begin
   map_we=1;map_wa=scan_addr;map_wd=2'b11;
  end else if(state==N_EVAL && map_q==2'b01 && tail<QUEUE_CAP)begin
   map_we=1;map_wa=naddr;map_wd=2'b11;
  end
  if(state==SCAN_EVAL && map_q==2'b01)queue_we=1;
  else if(state==N_EVAL && map_q==2'b01 && tail<QUEUE_CAP)begin
   queue_we=1;queue_wa=tail;queue_wd={ny[7:0],nx[7:0]};
  end
 end
 // One synchronous read + one write per RAM. Capture clears visited bits.
 always @(posedge clk)begin
  map_q<=bitmap[map_read_addr];work_q<=work_queue[work_read_addr];best_q<=best_queue[class_index];
  if(rst_n)begin
   if(map_we)bitmap[map_wa]<=map_wd;
   if(queue_we)work_queue[queue_wa]<=queue_wd;
   if(state==COPY_WRITE)best_queue[copy_index]<=work_q;
  end
 end
 wire lband=px<bxl+band,rband=px+band>bxr,tband=py<byt+band,bband=py+band>byb;
 wire [9:0] ax=dx<0?-dx:dx,ay=dy<0?-dy:dy;
 wire [2:0] sector={dx<0,dy<0,ax>ay};
 // Ignore interior duplicate strokes when validating the outer fitted curve.
 // Still require >= half of ALL original candidate points plus 90% coverage.
 wire envelope=ellipse_value>=(ellipse_rhs-(ellipse_rhs>>2));
 wire radial=ellipse_value>ellipse_rhs ?
  ellipse_value-ellipse_rhs<=(ellipse_rhs>>2) : ellipse_rhs-ellipse_value<=(ellipse_rhs>>2);
 wire nested_second=(sxl>=bxl && sxr<=bxr && syt>=byt && syb<=byb) ||
  (bxl>=sxl && bxr<=sxr && byt>=syt && byb<=syb);
 wire ambiguous=second_count>=16 && second_count*4>=best_count*3 && !nested_second;
 wire rect_coverage=nt*4>=w*3 && nb*4>=w*3 && nl*4>=h*3 && nr*4>=h*3;
 wire hollow_enough=(best_count-band_count)*2<=interior_area;
 wire rect_gaps=max_t<=((w/5>2)?w/5:2) && max_b<=((w/5>2)?w/5:2) &&
  max_l<=((h/5>2)?h/5:2) && max_r<=((h/5>2)?h/5:2);
 wire circle_coverage=cl*10>=(h-4)*9 && cr*10>=(h-4)*9 && ct*10>=(w-4)*9 && cb*10>=(w-4)*9;
 // synthesis translate_off
 initial begin
  if(S<1 || CW>255 || CH>255 || QUEUE_CAP<16 || QUEUE_CAP>8192 ||
     PROCESS_BUDGET<1 || PROCESS_BUDGET>1048575)
   $fatal(1,"Unsupported geometry dimensions, queue capacity or watchdog budget");
 end
 // synthesis translate_on
 always @(posedge clk)begin
  if(!rst_n)begin
   chosen_shape<=0;chosen_count<=0;candidates<=0;trial_shape<=0;
   win_l<=0;win_t<=0;win_r<=0;win_b<=0;win_lo<=0;win_hi<=0;trial_lo<=0;trial_hi<=0;
   row_lo<=0;row_hi<=0;win_tm<=0;win_bm<=0;win_lm<=0;win_rm<=0;win_sides<=0;win_radial<=0;
   a2<=0;b2<=0;xx<=0;yy<=0;weighted_x<=0;weighted_y<=0;ellipse_value<=0;ellipse_rhs<=0;
   shape<=0;left<=0;top<=0;right<=0;bottom<=0;
   debug_reason<=1;debug_cells<=0;debug_count<=0;debug_sides<=0;debug_radial<=0;
   support_top<=0;support_bottom<=0;support_left<=0;support_right<=0;
   state<=CAPTURE;vsq<=0;ready<=0;frame_seen<=0;frame_synced<=0;work_cycles<=0;raw_cells<=0;components<=0;
   horizontal<=0;row_or<=0;scan_addr<=0;naddr<=0;scan_x<=0;scan_y<=0;
   head<=0;tail<=0;copy_index<=0;class_index<=0;best_count<=0;second_count<=0;
   node_x<=0;node_y<=0;neighbor<=0;cxl<=0;cxr<=0;cyt<=0;cyb<=0;
   bxl<=0;bxr<=0;byt<=0;byb<=0;sxl<=0;sxr<=0;syt<=0;syb<=0;
   pending<=0;reason<=1;pl<=0;pt<=0;pr<=0;pb<=0;
   w<=0;h<=0;centerx<=0;centery<=0;radius<=0;radius2<=0;distance2<=0;interior_area<=0;dx<=0;dy<=0;px<=0;py<=0;
   band_count<=0;inliers<=0;envelope_count<=0;profile_pass<=0;top_mask<=0;bottom_mask<=0;left_mask<=0;right_mask<=0;
   ctop<=0;cbottom<=0;cleft<=0;cright<=0;corners<=0;sectors<=0;checkindex<=0;
   nt<=0;nb<=0;nl<=0;nr<=0;ct<=0;cb<=0;cl<=0;cr<=0;
   gap_t<=0;gap_b<=0;gap_l<=0;gap_r<=0;max_t<=0;max_b<=0;max_l<=0;max_r<=0;
  end else begin
   vsq<=ctl[2];
   if(ctl[2] && !vsq)begin
    frame_synced<=1;
    shape<=ready?chosen_shape:0;row_lo<=win_lo;row_hi<=win_hi;
    left<=(ready && chosen_shape!=0)?win_l:0;top<=(ready && chosen_shape!=0)?win_t:0;
    right<=(ready && chosen_shape!=0)?win_r:0;bottom<=(ready && chosen_shape!=0)?win_b:0;
    debug_reason<=ready?reason:(frame_seen?7:1);
    debug_cells<=raw_cells;debug_count<=chosen_count;debug_sides<=win_sides;
    debug_radial<=win_radial;
    support_top<=win_tm;support_bottom<=win_bm;support_left<=win_lm;support_right<=win_rm;
    ready<=0;pending<=0;chosen_shape<=0;chosen_count<=0;candidates<=0;win_sides<=0;win_radial<=0;reason<=1;frame_seen<=0;state<=CAPTURE;
    horizontal<=0;raw_cells<=0;components<=0;best_count<=0;second_count<=0;work_cycles<=0;
    scan_addr<=0;scan_x<=0;scan_y<=0;head<=0;tail<=0;
    top_mask<=0;bottom_mask<=0;left_mask<=0;right_mask<=0;nt<=0;nb<=0;nl<=0;nr<=0;inliers<=0;
   end else if(state!=CAPTURE && state!=DONE && work_cycles>=PROCESS_BUDGET)begin
    ready<=1;pending<=0;chosen_shape<=0;reason<=7;state<=DONE;
   end else begin
    if(state!=CAPTURE && state!=DONE)work_cycles<=work_cycles+1'b1;
    case(state)
     CAPTURE:if(roi && frame_synced)begin
      horizontal<=partial;
      if(ux%S==S-1 || ux==RW-1)row_or[cx]<=pooled;
      if(pool_write && pooled)raw_cells<=raw_cells+1'b1;
      if(ux==RW-1 && uy==RH-1)begin frame_seen<=1;state<=SCAN_READ;end
     end
     SCAN_READ:state<=SCAN_EVAL;
     SCAN_EVAL:if(map_q==2'b01)begin
      head<=0;tail<=1;cxl<=scan_x;cxr<=scan_x;cyt<=scan_y;cyb<=scan_y;
      components<=components+1'b1;state<=POP_READ;
     end else state<=NEXT_SCAN;
     POP_READ:state<=POP_LATCH;
     POP_LATCH:begin node_x<=work_q[7:0];node_y<=work_q[15:8];neighbor<=0;state<=N_ADDR;end
     N_ADDR:if(neighbor_valid)begin naddr<=ny*CW+nx;state<=N_READ;end else state<=N_NEXT;
     N_READ:state<=N_EVAL;
     N_EVAL:begin
      if(map_q==2'b01)begin
       if(tail>=QUEUE_CAP)begin reason<=6;pending<=0;chosen_shape<=0;ready<=1;state<=DONE;end
       else begin
        tail<=tail+1'b1;
        if(nx<cxl)cxl<=nx;if(nx>cxr)cxr<=nx;
        if(ny<cyt)cyt<=ny;if(ny>cyb)cyb<=ny;
        state<=N_NEXT;
       end
      end else state<=N_NEXT;
     end
     N_NEXT:if(neighbor==23)begin
      if(head+1<tail)begin head<=head+1'b1;state<=POP_READ;end else state<=COMP_DONE;
     end else begin neighbor<=neighbor+1'b1;state<=N_ADDR;end
     COMP_DONE:begin
      if(tail>=16 && cxr-cxl>=7 && cyb-cyt>=7)begin
       if(candidates>=8)begin chosen_shape<=0;reason<=5;ready<=1;state<=DONE;end
       else begin
        candidates<=candidates+1'b1;best_count<=tail;
        bxl<=cxl;bxr<=cxr;byt<=cyt;byb<=cyb;state<=CLASS_SETUP;
       end
      end else state<=NEXT_SCAN;
     end
     COPY_READ:state<=COPY_WRITE;
     COPY_WRITE:if(copy_index+1<best_count)begin copy_index<=copy_index+1'b1;state<=COPY_READ;end else state<=NEXT_SCAN;
     NEXT_SCAN:if(scan_addr==CELLS-1)begin ready<=1;if(chosen_shape!=0)reason<=0;else if(raw_cells==0)reason<=2;state<=DONE;end
      else begin
       scan_addr<=scan_addr+1'b1;
       if(scan_x==CW-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;
       state<=SCAN_READ;
      end
     CLASS_SETUP:begin
      w<={1'b0,bxr}-{1'b0,bxl}+1;h<={1'b0,byb}-{1'b0,byt}+1;
      centerx<={1'b0,bxl}+bxr;centery<={1'b0,byt}+byb;
      radius<=(({1'b0,bxr}-bxl)+({1'b0,byb}-byt))>>1;
      pl<=RX+bxl*S;pt<=RY+byt*S;pr<=RX+(bxr+1)*S-1;pb<=RY+(byb+1)*S-1;
      trial_lo<={CH{8'hff}};trial_hi<=0;top_mask<=0;bottom_mask<=0;left_mask<=0;right_mask<=0;
      class_index<=0;band_count<=0;inliers<=0;envelope_count<=0;profile_pass<=0;corners<=0;sectors<=0;
      ctop<=0;cbottom<=0;cleft<=0;cright<=0;
      if(best_count==0)begin reason<=2;pending<=0;ready<=1;state<=DONE;end else state<=CLASS_READ;
     end
     CLASS_READ:begin
      a2<=(w-9'd1)*(w-9'd1);b2<=(h-9'd1)*(h-9'd1);radius2<=radius*radius;interior_area<=(w>4 && h>4)?(w-9'd4)*(h-9'd4):18'd0;
      state<=CLASS_CALC;
     end
     CLASS_CALC:begin
      px<=work_q[7:0];py<=work_q[15:8];
      dx<=$signed({1'b0,work_q[7:0],1'b0})-$signed({1'b0,centerx});
      dy<=$signed({1'b0,work_q[15:8],1'b0})-$signed({1'b0,centery});state<=CLASS_DIST;
     end
     CLASS_DIST:begin xx<=dx*dx;yy<=dy*dy;ellipse_rhs<=a2*b2;state<=ELLIPSE_SUM;end
     ELLIPSE_SUM:begin weighted_x<=xx*b2;weighted_y<=yy*a2;state<=ELLIPSE_READY;end
     ELLIPSE_READY:begin ellipse_value<=weighted_x+weighted_y;state<=CLASS_ACC;end
     CLASS_ACC:begin
      if(!profile_pass)begin
      if(px<trial_lo[py*8+:8])trial_lo[py*8+:8]<=px;
      if(px>trial_hi[py*8+:8])trial_hi[py*8+:8]<=px;
      if(lband || rband || tband || bband)band_count<=band_count+1'b1;
      if(lband)left_mask[py]<=1;if(rband)right_mask[py]<=1;
      if(tband)top_mask[px]<=1;if(bband)bottom_mask[px]<=1;
      // A diagonal (1,1) sample alone is not an intersection: coarse small
      // circles have exactly those samples and must not become SQUARE.
      if(lband && tband && (px-bxl+py-byt<=corner_tol))corners[0]<=1;
      if(rband && tband && (bxr-px+py-byt<=corner_tol))corners[1]<=1;
      if(lband && bband && (px-bxl+byb-py<=corner_tol))corners[2]<=1;
      if(rband && bband && (bxr-px+byb-py<=corner_tol))corners[3]<=1;
      end
      if(profile_pass && envelope)envelope_count<=envelope_count+1'b1;
      if(profile_pass && envelope && radial)begin
       inliers<=inliers+1'b1;sectors[sector]<=1;
       if(dx<=0)cleft[py]<=1;if(dx>=0)cright[py]<=1;
       if(dy<=0)ctop[px]<=1;if(dy>=0)cbottom[px]<=1;
      end
      if(class_index+1<best_count)begin class_index<=class_index+1'b1;state<=CLASS_READ;end
      else if(!profile_pass)begin profile_pass<=1;class_index<=0;state<=CLASS_READ;end
      else begin
       checkindex<=0;nt<=0;nb<=0;nl<=0;nr<=0;ct<=0;cb<=0;cl<=0;cr<=0;
       gap_t<=0;gap_b<=0;gap_l<=0;gap_r<=0;max_t<=0;max_b<=0;max_l<=0;max_r<=0;
       state<=MASK_SCAN;
      end
     end
     MASK_SCAN:begin
      if(checkindex>=bxl && checkindex<=bxr && checkindex<CW)begin
       if(top_mask[checkindex])begin nt<=nt+1'b1;gap_t<=0;end
       else begin gap_t<=gap_t+1'b1;if(gap_t+1>max_t)max_t<=gap_t+1'b1;end
       if(bottom_mask[checkindex])begin nb<=nb+1'b1;gap_b<=0;end
       else begin gap_b<=gap_b+1'b1;if(gap_b+1>max_b)max_b<=gap_b+1'b1;end
      end
      if(checkindex>=byt && checkindex<=byb && checkindex<CH)begin
       if(left_mask[checkindex])begin nl<=nl+1'b1;gap_l<=0;end
       else begin gap_l<=gap_l+1'b1;if(gap_l+1>max_l)max_l<=gap_l+1'b1;end
       if(right_mask[checkindex])begin nr<=nr+1'b1;gap_r<=0;end
       else begin gap_r<=gap_r+1'b1;if(gap_r+1>max_r)max_r<=gap_r+1'b1;end
      end
      if(checkindex>byt+1 && checkindex+1<byb && checkindex<CH)begin
       if(cleft[checkindex])cl<=cl+1'b1;if(cright[checkindex])cr<=cr+1'b1;
      end
      if(checkindex>bxl+1 && checkindex+1<bxr && checkindex<CW)begin
       if(ctop[checkindex])ct<=ct+1'b1;if(cbottom[checkindex])cb<=cb+1'b1;
      end
      if(checkindex>=CW && checkindex>=CH)state<=DECIDE;else checkindex<=checkindex+1'b1;
     end
     DECIDE:begin
      if(best_count>=16 && w>=8 && h>=8 && bxl>0 && byt>0 && bxr<CW-1 && byb<CH-1)begin
       if(rect_coverage && rect_gaps && (&corners) && hollow_enough && band_count*5>=best_count*4 && w<=h*5 && h<=w*5)begin
        if(best_count>chosen_count)begin chosen_shape<=((w>h?w-h:h-w)<=(w>h?w:h)/8)?2:3;chosen_count<=best_count;win_l<=pl;win_t<=pt;win_r<=pr;win_b<=pb;win_lo<=trial_lo;win_hi<=trial_hi;win_tm<=top_mask;win_bm<=bottom_mask;win_lm<=left_mask;win_rm<=right_mask;win_sides<={nt,nb,nl,nr};win_radial<=inliers>255?255:inliers;end
       end else if(w>=12 && h>=12 && (&sectors) && circle_coverage && inliers*20>=envelope_count*17 && envelope_count>=16 && inliers*2>=best_count && w<=h*3 && h<=w*3)begin
        if(best_count>chosen_count)begin chosen_shape<=(w*8<=h*9 && h*8<=w*9)?1:4;chosen_count<=best_count;win_l<=pl;win_t<=pt;win_r<=pr;win_b<=pb;win_lo<=trial_lo;win_hi<=trial_hi;win_tm<=top_mask;win_bm<=bottom_mask;win_lm<=left_mask;win_rm<=right_mask;win_sides<={nt,nb,nl,nr};win_radial<=inliers>255?255:inliers;end
       end else reason<=8;
      end else reason<=3;
      state<=NEXT_SCAN;
     end
    endcase
   end
  end
 end
endmodule
`default_nettype wire
