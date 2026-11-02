from pathlib import Path
import os,hashlib,json
os.environ['RTL_SIM']='icarus_direct';os.environ['VVP']='D:/FPGAdemo/tools/iverilog/app/bin/vvp.exe'
import run_tests as s
from verify_g1r_cases import polygon
from verify_g2_shapes import oval
r=Path(__file__).resolve().parents[1];d=r/'sim/g2_negatives';d.mkdir(exist_ok=True)
items=[('triangle',polygon([(256,112),(176,260),(336,260)])),('diamond',polygon([(256,120),(328,192),(256,264),(184,192)])),('arc30',{(x,y) for x,y in oval(256,192,60,60) if not (0.5236<__import__('math').atan2(y-192,x-256)<1.0472)}),('small_circle',oval(256,192,14,14))]
rows=[]
for name,points in items:
 f=d/(name+'.hex');f.write_text(''.join(f'{y*512+x:08x}\n' for x,y in sorted(points,key=lambda p:(p[1],p[0]))));rows.append(f'{name} {f.name} {len(points)} 0 0 0 0 0 0\n')
(d/'cases_512.txt').write_text(''.join(rows));s.BUILD=r/'sim/build_g2_negatives';s.BUILD.mkdir(exist_ok=True)
s.RTL=[r/'rtl/edge/video/img_coords.sv',r/'rtl/edge/geometry/img_geometry.sv'];p=s.BUILD/'ref.sv';p.write_text((r/'reference/G1_failed_revision/img_geometry.sv').read_text().replace('module img_geometry','module g1r_reference_geometry'));s.TB_RTL['tb_g1r_raster']=[str(p)]
h=hashlib.sha256((r/'rtl/edge/geometry/img_geometry.sv').read_bytes()).hexdigest()
s.run('tb_g1r_raster',{'HAS_DIAGNOSTICS':1,'DATA_DIR':'"'+d.as_posix()+'"'})
assert h==hashlib.sha256((r/'rtl/edge/geometry/img_geometry.sv').read_bytes()).hexdigest()
(r/'reports/g2_negatives.json').write_text(json.dumps(dict(status='PASS',source_sha256=h,cases=[x[0] for x in items])))
