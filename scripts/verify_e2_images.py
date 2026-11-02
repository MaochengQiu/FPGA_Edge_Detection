"""Actual RTL comparison: NMS24 vs NMS50 vs local graph H50/L25."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parents[1]/'tools/python_libs'))
import numpy as np
from PIL import Image,ImageDraw
from verify_e1 import sobel,topology
from e2_model import descriptor,local_link
import run_tests as sim
BUILD=ROOT/'sim/build';INPUT=ROOT/'reference/e2_inputs';OUT=ROOT/'reports/e2_ab'
INPUT.mkdir(exist_ok=True);OUT.mkdir(exist_ok=True)

def inputs():
    names=['checker','cup_pattern','printed_text','pcb_tracks','face_photo','motion_0','motion_1','motion_2']
    images=[Image.open(ROOT/'reference/e1_inputs'/f'{n}.png').convert('RGB') for n in names]
    kinds=['synthetic','synthetic','synthetic','synthetic','public_real_photo','synthetic_sequence','synthetic_sequence','synthetic_sequence']
    yy,xx=np.indices((192,256));a=np.full((192,256),40,np.uint8)
    a[12:180,80:176]=80;a[90:93,80:176]=48
    names.append('weak_band');images.append(Image.fromarray(a).convert('RGB'));kinds.append('synthetic_known_band')
    rng=np.random.default_rng(123)
    for sigma in (3,4,5,6):
        noise=np.clip(64+rng.normal(0,sigma,(192,256)),0,255).astype('uint8')
        names.append(f'flat_noise_{sigma}');images.append(Image.fromarray(noise).convert('RGB'));kinds.append('synthetic_known_flat_background')
    metadata=[]
    for name,im,kind in zip(names,images,kinds):
        p=INPUT/f'{name}.png'
        if not p.exists():im.save(p)
        metadata.append(dict(name=name,kind=kind,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
    (INPUT/'inputs.json').write_text(json.dumps(metadata,indent=2))
    return names,images,metadata

def main():
    names,images,meta=inputs();w,h=images[0].size;ht=w+32;L=5*ht+60
    refs=[sobel(im) for im in images];expected_ctl=[]
    with (BUILD/'e2_vectors.txt').open('w') as f:
        for im in images:
            a=np.array(im)
            for sy in range(h+16):
                for x in range(ht):
                    de=2<=sy<h+2 and x<w;hs=x==w+1;vs=sy==0
                    r,g,b=map(int,a[sy-2,x]) if de else (0,0,0)
                    f.write(f'{(r<<16)|(g<<8)|b:06x} {int(de)} {int(hs)} {int(vs)}\n')
                    expected_ctl.append((int(de),int(hs),int(vs)))
        f.write('000000 0 0 0\n'*(L+4));expected_ctl += [(0,0,0)]*(L+4)
    delayed_ctl=[(0,0,0)]*(L-1)+expected_ctl
    observed={}
    for name,enabled,high in (('N24',0,24),('N50',0,50),('L50',1,50)):
        sim.run('tb_e2_image',{'WIDTH':w,'HEIGHT':h,'HTOTAL':ht,'LINK_ENABLE':enabled,'HIGH':high})
        pix=[]
        with (BUILD/'e2_observed.txt').open() as f:
            for i,line in enumerate(f):
                color,de,hs,vs=line.split();ctl=tuple(map(int,(de,hs,vs)))
                assert ctl==delayed_ctl[i],('E2 image sync',name,i,ctl,delayed_ctl[i])
                if ctl[0]:
                    c=int(color,16);assert c in (0,0xffffff);pix.append(c!=0)
        assert len(pix)==len(images)*w*h
        observed[name]=np.array(pix,dtype=bool).reshape(len(images),h,w)
        (ROOT/f'reports/e2_image_{name}.log').write_text((BUILD/'tb_e2_image_run.log').read_text())
    rows=[];sheet=Image.new('RGB',(w*4,(h+32)*len(images)),(20,20,20));draw=ImageDraw.Draw(sheet)
    for i,(name,im,ref) in enumerate(zip(names,images,refs)):
        m,d,v,k=ref;a,c,s,dr=descriptor(m,d,k,50);linked=local_link(a,c,s,dr)
        expected={'N24':k&(m>=24),'N50':k&(m>=50),'L50':linked}
        for variant in expected:
            assert np.array_equal(observed[variant][i],expected[variant]),('actual RTL mismatch',name,variant)
        assert not np.any(linked & (m<25)),'Invented weak edges without raw gradient'
        row=dict(name=name,kind=meta[i]['kind'],N24=topology(expected['N24']),N50=topology(expected['N50']),L50=topology(linked))
        if name=='weak_band':
            row['known_vertical_band_coverage']={v:int(mask[90:93,79:81].any(axis=1).sum()) for v,mask in expected.items()}
        if name.startswith('flat_noise'):
            row['known_background_false_pixels']={v:int(mask[5:-5,5:-5].sum()) for v,mask in expected.items()}
        rows.append(row)
        panels=[im]+[Image.fromarray((observed[v][i]*255).astype('uint8')).convert('RGB') for v in ('N24','N50','L50')]
        y=i*(h+32)
        for j,(label,p) in enumerate(zip((name,'NMS H24','NMS H50','E2 local H50 L25'),panels)):
            draw.text((j*w+4,y+3),label,fill='white');sheet.paste(p,(j*w,y+28))
        for v,p in zip(('input','N24','N50','L50'),panels):p.save(OUT/f'{name}_{v}.png')
    sheet.save(OUT/'comparison.png')
    report=dict(status='PASS',rtl_outputs=len(images)*3,fixtures=rows,
        high=50,low=25,min_component=3,min_seeds=3,direction_constrained=True,
        latency_cycles=L,kernel_1080p_cycles=11060,added_over_E1_us=4433/148.5,
        limits='Exact within a 5x5 direction-constrained graph; not full-image hysteresis. Tiny real features and long weak runs may be removed.',
        ground_truth='No human annotations. Only synthetic flat ROIs and known weak bands have analytic labels.')
    (ROOT/'reports/e2_image_verification.json').write_text(json.dumps(report,indent=2))
    print('E2 IMAGE VERIFICATION PASS: actual RTL N24/N50/L50, oracle and sync exact; descriptive and synthetic-only noise/connection metrics')
if __name__=='__main__':main()
