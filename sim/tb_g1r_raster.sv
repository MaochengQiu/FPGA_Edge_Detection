`timescale 1ns/1ps
// Sparse addresses describe *pixels*, not the DUT's pooled bitmap.
// A real DE/HS raster is generated here; no Python per-clock stimulus dump.
module tb_g1r_raster #(
 parameter WIDTH=512, HEIGHT=384, S=4,
 parameter HTOTAL=(WIDTH==1920 ? 2200 : 640),
 parameter VTOTAL=(HEIGHT==1080 ? 1125 : HEIGHT),
 parameter EXTRA_BLANK=0,
 parameter DATA_DIR="../g1r_data", CASE_START=0, CASE_END=10000,
 parameter REFERENCE=0, HAS_DIAGNOSTICS=0, TIMEOUT_TEST=0,
 parameter RESET_TEST=0, BUDGET_TEST=0, STARTUP_TEST=0
);
 reg clk=0, rst_n=0, edge_pixel=0;
 reg [3:0] ctl=0;
 always #5 clk=~clk;
 wire [2:0] shape;
 wire [15:0] left,top,right,bottom;
 wire [3:0] reason;
 wire [15:0] cells,count;
 wire [31:0] sides;
 wire [7:0] radial;
 wire [19:0] observed_cycles;
 wire observed_ready;
 wire [1:0] observed_pending;
 generate
  if(REFERENCE) begin: reference_dut
   g1r_reference_geometry #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.S(S)) dut
    (.clk(clk),.rst_n(rst_n),.edge_pixel(edge_pixel),.ctl(ctl),
     .shape(shape),.left(left),.top(top),.right(right),.bottom(bottom));
   assign reason=0; assign cells=0; assign count=0; assign sides=0; assign radial=0;
   assign observed_cycles=0;assign observed_ready=1;assign observed_pending=0;
  end else if(HAS_DIAGNOSTICS) begin: diagnostic_dut
   img_geometry #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.S(S),
                  .PROCESS_BUDGET(BUDGET_TEST?128:400000)) dut
    (.clk(clk),.rst_n(rst_n),.edge_pixel(edge_pixel),.ctl(ctl),
     .shape(shape),.left(left),.top(top),.right(right),.bottom(bottom),
     .debug_reason(reason),.debug_cells(cells),.debug_count(count),
     .debug_sides(sides),.debug_radial(radial));
   assign observed_cycles=dut.work_cycles;
   assign observed_ready=dut.ready;
   assign observed_pending=dut.pending;
  end else begin: original_ports_dut
   img_geometry #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.S(S)) dut
    (.clk(clk),.rst_n(rst_n),.edge_pixel(edge_pixel),.ctl(ctl),
     .shape(shape),.left(left),.top(top),.right(right),.bottom(bottom));
   assign reason=0; assign cells=0; assign count=0; assign sides=0; assign radial=0;
   assign observed_cycles=0;assign observed_ready=1;assign observed_pending=0;
  end
 endgenerate

 // Every output bit must hold between VS rising edges, including blanking.
 reg [66:0] held=0;
 reg [75:0] held_diag=0;
 reg previous_vs=0, monitor_enable=0;
 always @(posedge clk) begin
  #1;
  if(rst_n && monitor_enable && !(ctl[2] && !previous_vs)) begin
   if({shape,left,top,right,bottom} !== held)
    $fatal(1,"G1R TEMPORAL output changed between commits got=%h previous=%h",{shape,left,top,right,bottom},held);
   if(HAS_DIAGNOSTICS && {reason,cells,count,sides,radial} !== held_diag)
    $fatal(1,"G1R TEMPORAL diagnostics changed between commits");
  end
  held={shape,left,top,right,bottom};
  held_diag={reason,cells,count,sides,radial};
  previous_vs=ctl[2];
 end

 reg [31:0] pixels[0:599999];
 integer fd, rc, ordinal, n, expected, el,et,er,eb,tolerance;
 integer x,y,pointer,address,frames=0,failures=0,rounds,round,short_frame;
 reg [1023:0] case_name,pixel_file;
 reg [2047:0] list_file,full_path;

 function integer absdiff(input integer a,b);
  absdiff=(a>b)?a-b:b-a;
 endfunction

 task commit;
  begin
   @(negedge clk);
   if(WIDTH==1920 && monitor_enable && HAS_DIAGNOSTICS) begin
    $display("G1R BUDGET case=%0s cycles=%0d ready=%0d pending=%0d",case_name,observed_cycles,observed_ready,observed_pending);
    if(observed_ready!==1'b1) $fatal(1,"G1R HD result not ready before next VS");
    if(observed_cycles>400000) $fatal(1,"G1R processing exceeded configured budget");
   end
   ctl=4; edge_pixel=0;
   @(posedge clk); #2;
  end
 endtask

 task reset_during_processing;
  begin
   // Previous successful frame leaves both RAMs and published outputs dirty.
   raster(1);
   @(negedge clk);ctl=0;edge_pixel=0;
   repeat(50) @(negedge clk);
   monitor_enable=0;rst_n=0;
   repeat(4) @(negedge clk);
   @(posedge clk);#2;
   if({shape,left,top,right,bottom}!==67'b0)
    $fatal(1,"G1R reset failed to clear published result");
   if(HAS_DIAGNOSTICS && {reason,cells,count,sides,radial}!=={4'd1,72'd0})
    $fatal(1,"G1R reset diagnostics not warm/empty");
   @(negedge clk);rst_n=1;
   commit();
   if({shape,left,top,right,bottom}!==67'b0)
    $fatal(1,"G1R reset re-published a stale result");
   monitor_enable=1;
   $display("G1R RESET CLEAR PASS; next full frame must recover");
  end
 endtask

 task check_result(input integer wanted);
  reg good;
  begin
   good=(shape===wanted[2:0]);
   if(wanted!=0)
    good=good && (^{left,top,right,bottom}!==1'bx) &&
     absdiff(left,el)<=tolerance && absdiff(top,et)<=tolerance &&
     absdiff(right,er)<=tolerance && absdiff(bottom,eb)<=tolerance;
   else if(!REFERENCE)
    // NONE must not carry a stale target box; overlay testing is separate.
    good=good && ({left,top,right,bottom}===64'b0);
   if(!good) begin
    failures=failures+1;
    $display("G1R MISMATCH case=%0s frame=%0d expected=%0d box=%0d,%0d,%0d,%0d tol=%0d got=%0d box=%0d,%0d,%0d,%0d reason=%h cells=%0d count=%0d sides=%h radial=%h",
     case_name,frames,wanted,el,et,er,eb,tolerance,shape,left,top,right,bottom,reason,cells,count,sides,radial);
   end else $display("G1R CASE PASS case=%0s frame=%0d shape=%0d box=%0d,%0d,%0d,%0d reason=%h cells=%0d count=%0d sides=%h radial=%h",
    case_name,frames,shape,left,top,right,bottom,reason,cells,count,sides,radial);
   if(HAS_DIAGNOSTICS && (^{reason,cells,count,sides,radial}===1'bx))
    $fatal(1,"G1R unknown diagnostic outputs at commit");
  end
 endtask

 task raster(input integer shortened);
  integer xmax,ymax;
  begin
   pointer=0;
   @(negedge clk);ctl=0;
   ymax=shortened ? HEIGHT/4+HEIGHT/2 : VTOTAL;
   for(y=0;y<ymax;y=y+1) begin
    xmax=(shortened && y==ymax-1) ? WIDTH/4+WIDTH/2 : HTOTAL;
    for(x=0;x<xmax;x=x+1) begin
     @(negedge clk);
     ctl=0; ctl[0]=(x<WIDTH && y<HEIGHT); ctl[1]=(x==WIDTH+8);
     edge_pixel=0;
     if(ctl[0]) begin
      address=y*WIDTH+x;
      if(pointer<n && pixels[pointer]==address) begin
       edge_pixel=1; pointer=pointer+1;
      end
     end
    end
   end
   if(pointer!=n) $fatal(1,"G1R stimulus not completely consumed %0d/%0d",pointer,n);
   if(!shortened) begin
    @(negedge clk);ctl=0;edge_pixel=0;
    repeat(EXTRA_BLANK) @(negedge clk);
   end
  end
 endtask

 initial begin
  if(WIDTH==1920) $sformat(list_file,"%0s/cases_1920.txt",DATA_DIR);
  else $sformat(list_file,"%0s/cases_512.txt",DATA_DIR);
  fd=$fopen(list_file,"r");
  if(!fd) $fatal(1,"G1R missing data %0s; run scripts/verify_g1r_cases.py --generate-only",list_file);
  repeat(5) @(negedge clk);rst_n=1;
  if(STARTUP_TEST) begin
   rc=$fscanf(fd,"%s %s %d %d %d %d %d %d %d\n",case_name,pixel_file,n,expected,el,et,er,eb,tolerance);
   if(rc!=9 || n==0) $fatal(1,"G1R startup needs a positive fixture");
   $sformat(full_path,"%0s/%0s",DATA_DIR,pixel_file);
   $readmemh(full_path,pixels,0,n-1);
   monitor_enable=1;
   raster(1);
   @(negedge clk);ctl=0;edge_pixel=0;
   repeat(EXTRA_BLANK) @(negedge clk);
   if({shape,left,top,right,bottom}!==67'b0) $fatal(1,"G1R pre-first-VS raster published a result");
   rc=$fseek(fd,0,0);
   if(rc) $fatal(1,"G1R startup cannot rewind manifest");
  end
  commit();
  if({shape,left,top,right,bottom}!==67'b0) $fatal(1,"G1R reset/first empty commit");
  if(STARTUP_TEST && HAS_DIAGNOSTICS && reason!==4'd1)
   $fatal(1,"G1R pre-first-VS raster was treated as an armed frame reason=%0d",reason);
  if(STARTUP_TEST) $display("G1R STARTUP UNARMED PASS; next complete frame must recover");
  monitor_enable=1;
  ordinal=0;
  while(!$feof(fd)) begin
   rc=$fscanf(fd,"%s %s %d %d %d %d %d %d %d\n",case_name,pixel_file,n,expected,el,et,er,eb,tolerance);
   if(rc!=9) $fatal(1,"G1R malformed case row %0d fields=%0d",ordinal,rc);
   if(ordinal>=CASE_START && ordinal<=CASE_END && (!(TIMEOUT_TEST || RESET_TEST || BUDGET_TEST) || ordinal==0)) begin
    if(n<0 || n>600000) $fatal(1,"G1R invalid sparse input count");
    $sformat(full_path,"%0s/%0s",DATA_DIR,pixel_file);
    if(n>0) $readmemh(full_path,pixels,0,n-1);
    rounds=TIMEOUT_TEST?3:(RESET_TEST?2:1);
    for(round=0;round<rounds;round=round+1) begin
     short_frame=TIMEOUT_TEST && round==1;
     raster(short_frame);
     // Commit immediately after the last ROI pixel for the timeout round.
     // Other rounds have an entire raster and the configured blank budget.
     commit(); frames=frames+1;
     check_result((short_frame || BUDGET_TEST)?0:expected);
     if(HAS_DIAGNOSTICS && (short_frame || BUDGET_TEST) && reason!==4'd7)
      $fatal(1,"G1R deadline must report reason7, got %0d",reason);
     // Hold VS high: level-sensitive publication is also prohibited.
     repeat(3) @(negedge clk);
     if(RESET_TEST && round==0) reset_during_processing();
    end
   end
   ordinal=ordinal+1;
  end
  $fclose(fd);
  if(frames==0) $fatal(1,"G1R selected no cases");
  if(REFERENCE) $display("G1R REFERENCE DONE frames=%0d mismatches=%0d",frames,failures);
  else begin
   if(failures) $fatal(1,"G1R FAIL frames=%0d mismatches=%0d",frames,failures);
   $display("G1R RASTER PASS width=%0d height=%0d frames=%0d timeout_test=%0d",WIDTH,HEIGHT,frames,TIMEOUT_TEST);
  end
  $finish;
 end
 // A broken bench or simulator must not leave an unbounded job.
 initial begin #3000000000; $fatal(1,"G1R simulation watchdog"); end
endmodule
