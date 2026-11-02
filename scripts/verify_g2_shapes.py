from pathlib import Path
import math,json,sys,os,hashlib
import run_tests as sim
ROOT=Path(__file__).resolve().parents[1]; D=ROOT/'sim/g2_cases';D.mkdir(exist_ok=True)
def poly(l,t,r,b):return {(x,t) for x in range(l,r+1)}|{(x,b) for x in range(l,r+1)}|{(l,y) for y in range(t,b+1)}|{(r,y) for y in range(t,b+1)}
def oval(cx,cy,rx,ry):return {(round(cx+rx*math.cos(i*math.tau/4096)),round(cy+ry*math.sin(i*math.tau/4096))) for i in range(4096)}
def run(w,h):
 rx,ry=w//4,h//4; rows=[]; cases=[]
 def add(name,p,shape,target=None):
  p=set(p); target=p if target is None else target
  if shape:
   xx,yy=zip(*target);box=[rx+(min(xx)-rx)//4*4,ry+(min(yy)-ry)//4*4,rx+((max(xx)-rx)//4+1)*4-1,ry+((max(yy)-ry)//4+1)*4-1]
  else:box=[0]*4
  name=str(w)+'_'+name;f=D/(name+'.hex');f.write_text(''.join(f'{y*w+x:08x}\n' for x,y in sorted(p,key=lambda q:(q[1],q[0]))))
  rows.append(f'{name} {f.name} {len(p)} {shape} '+ ' '.join(map(str,box))+' 3\n');cases.append(dict(name=name,shape=shape))
 if w==512:
  for rad in [24,32,44,60]:
   for k in range(4):add(f'circle{rad}_phase{k}',oval(256+k,192+k,rad,rad),1)
  for a,b in [(60,28),(60,40),(28,60)]:
   for k in range(4):add(f'ellipse{a}_{b}_phase{k}',oval(256+k,192+k,a,b),4)
  for thick in [4,8,12]:add(f'double_circle{thick}',oval(256,192,60,60)|oval(256,192,60-thick,60-thick),1,target=oval(256,192,60,60))
  for size in [48,80,128]:
   p=poly(256-size//2,192-size//2,255+size//2,191+size//2);add(f'square{size}',p,2)
  for thick in [4,12,24]:
   p=poly(176,128,335,255)|poly(176+thick,128+thick,335-thick,255-thick);add(f'double_rect{thick}',p,3,target=poly(176,128,335,255))
  p=oval(300,192,48,28);bad=poly(140,112,220,271);bad={q for q in bad if q[1]!=112};add('larger_bad_with_ellipse',p|bad,4,target=p)
  add('ellipse_with_text',oval(256,192,60,36)|poly(240,180,271,203),4,target=oval(256,192,60,36))
  add('arc', {q for q in oval(256,192,60,40) if not(q[0]>256 and q[1]<192)},0)
  add('dense',{(x,y) for y in range(128,256) for x in range(176,304)},0)
  add('blank',set(),0)
 else:
  for name,a,b,shape in [('circle',120,120,1),('ellipse',200,100,4)]:add(name,oval(960,540,a,b),shape)
  add('rectangle',poly(700,420,1199,659),3)
  add('blank',set(),0)
 (D/('cases_1920.txt' if w==1920 else 'cases_512.txt')).write_text(''.join(rows))
 before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'rtl/edge').glob('*/*.sv')}
 sim.BUILD=ROOT/f'sim/build_g2_{w}';sim.BUILD.mkdir(exist_ok=True)
 sim.RTL=[ROOT/'rtl/edge/video/img_coords.sv',ROOT/'rtl/edge/geometry/img_geometry.sv']
 old=ROOT/'reference/G1_failed_revision/img_geometry.sv';ref=sim.BUILD/'ref.sv';ref.write_text(old.read_text().replace('module img_geometry','module g1r_reference_geometry'))
 sim.TB_RTL['tb_g1r_raster']=[str(ref)]
 sim.run('tb_g1r_raster',dict(WIDTH=w,HEIGHT=h,HAS_DIAGNOSTICS=1,DATA_DIR='"'+D.as_posix()+'"'))
 assert before=={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'rtl/edge').glob('*/*.sv')}
 (ROOT/f'reports/g2_shapes_{w}.json').write_text(json.dumps(dict(status='PASS',cases=cases,source=before,board_tested=False),indent=2))
if __name__=='__main__':
 os.environ.setdefault('RTL_SIM','icarus_direct');os.environ.setdefault('VVP','D:/FPGAdemo/tools/iverilog/app/bin/vvp.exe');sim.BACKEND='icarus_direct';sim.VVP=os.environ['VVP']
 for w,h in [(512,384),(1920,1080)]:run(w,h)
