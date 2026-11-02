"""Same-input actual RTL E2-algorithm/E3 comparison at H50 and H68."""
from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageDraw
from verify_e2_images import inputs
from verify_e1 import sobel,topology
from e2_model import descriptor,local_link
from e3_model import e3_link
import run_tests as sim

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'sim/build_e3_images';BUILD.mkdir(parents=True,exist_ok=True);sim.BUILD=BUILD
OUT=ROOT/'reports/e3_ab';OUT.mkdir(exist_ok=True)


def main():
    names,images,meta=inputs();w,h=images[0].size;ht=w+32;latency=5*ht+60
    refs=[sobel(im) for im in images];ctls=[]
    with (BUILD/'e2_vectors.txt').open('w') as f:
        for im in images:
            pixels=np.asarray(im)
            for sy in range(h+16):
                for x in range(ht):
                    de=2<=sy<h+2 and x<w; hs=x==w+1;vs=sy==0
                    r,g,b=map(int,pixels[sy-2,x]) if de else (0,0,0)
                    f.write(f'{(r<<16)|(g<<8)|b:06x} {int(de)} {int(hs)} {int(vs)}\n')
                    ctls.append((int(de),int(hs),int(vs)))
        f.write('000000 0 0 0\n'*(latency+4));ctls += [(0,0,0)]*(latency+4)
    ref_ctl=[(0,0,0)]*(latency-1)+ctls
    observed={}
    for high in (50,68):
        for enabled in (0,1):
            name=f'{"W" if enabled else "B"}{high}'
            sim.run('tb_e2_image',dict(WIDTH=w,HEIGHT=h,HTOTAL=ht,HIGH=high,LINK_ENABLE=1,WEAK_CHAIN_ENABLE=enabled))
            pix=[]
            for i,line in enumerate((BUILD/'e2_observed.txt').read_text().splitlines()):
                color,de,hs,vs=line.split();ctl=tuple(map(int,(de,hs,vs)))
                assert ctl==ref_ctl[i],('sync',name,i,ctl,ref_ctl[i])
                if ctl[0]:
                    value=int(color,16);assert value in (0,0xffffff);pix.append(value!=0)
            assert len(pix)==len(images)*w*h
            observed[name]=np.asarray(pix,bool).reshape(len(images),h,w)
            (ROOT/f'reports/e3_image_{name}.log').write_text((BUILD/'tb_e2_image_run.log').read_text())
    rows=[];sheet=Image.new('RGB',(w*5,(h+28)*len(images)),(20,20,20));draw=ImageDraw.Draw(sheet)
    for i,(name,im,(mag,dr,valid,keep)) in enumerate(zip(names,images,refs)):
        row=dict(name=name,kind=meta[i]['kind'])
        for high in (50,68):
            a,c,s,d=descriptor(mag,dr,keep,high)
            base=local_link(a,c,s,d);weak=e3_link(a,c,s,d)
            for variant,expected in ((f'B{high}',base),(f'W{high}',weak)):
                assert np.array_equal(observed[variant][i],expected),('RTL/oracle',name,variant)
                row[variant]=topology(expected)
                if name.startswith('flat_noise'):
                    row[variant]['known_flat_roi_false_pixels']=int(expected[5:-5,5:-5].sum())
                Image.fromarray((expected*255).astype('uint8')).save(OUT/f'{name}_{variant}.png')
            assert not np.any(base & ~weak),'Supplement deleted E2 output'
            assert not np.any(weak & (mag<(high+1)//2)),'unsupported low gradient invented'
            row[f'added_H{high}']=int((weak&~base).sum())
        rows.append(row)
        for col,(label,panel) in enumerate([(name,im)]+[(v,Image.fromarray((observed[v][i]*255).astype('uint8')).convert('RGB')) for v in ('B50','W50','B68','W68')]):
            draw.text((col*w+3,i*(h+28)+3),label,fill='white');sheet.paste(panel,(col*w,i*(h+28)+24))
    sheet.save(OUT/'comparison.png')
    report=dict(status='PASS',rtl_outputs=len(images)*4,fixtures=rows,preprocess=0,latency_cycles=latency,
        original_E2_is_subset=True,ground_truth='Only flat-noise fixtures have analytic background labels; no board capture or human contour labels',
        limits='Strict local straight-run supplement. Some extra noise pixels are possible; real quality requires board comparison.')
    (ROOT/'reports/e3_image_verification.json').write_text(json.dumps(report,indent=2))
    print('E3 IMAGE PASS',len(images)*4,'RTL outputs; per-pixel oracle and every sync token checked')


if __name__=='__main__':main()
