"""Fixed-input quality probe. All pixel outputs are actual RTL, checked against an integer oracle.
Synthetic noise ROIs / vertical step coverage are the only analytic quality labels.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image,ImageDraw
import run_tests as sim
from verify_e1 import direction,thin,topology
from e2_model import descriptor,local_link

ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'sim/build_e7_images'
BUILD.mkdir(parents=True,exist_ok=True);sim.BUILD=BUILD
OUT=ROOT/'reports/e7_quality';OUT.mkdir(exist_ok=True)
W,H,HT=128,96,160

def fixtures():
    names=[];images=[];meta=[];rng=np.random.default_rng(7001)
    for name in ('cup_pattern','printed_text','face_photo'):
        images.append(Image.open(ROOT/f'reference/e1_inputs/{name}.png').convert('RGB').resize((W,H),Image.Resampling.LANCZOS))
        names.append(name);meta.append(dict(kind='resized existing fixture, no contour truth'))
    yy,xx=np.indices((H,W))
    for sigma in (3,5,8):
        a=np.clip(64+rng.normal(0,sigma,(H,W)),0,255).astype('uint8')
        names.append(f'flat_noise_{sigma}');images.append(Image.fromarray(a).convert('RGB'));meta.append(dict(kind='known flat background',sigma=sigma))
    for delta in (20,80):
        a=64+(xx>=W//2)*delta+rng.normal(0,3,(H,W))
        images.append(Image.fromarray(np.clip(a,0,255).astype('uint8')).convert('RGB'))
        names.append(f'noisy_step_{delta}');meta.append(dict(kind='known vertical boundary',contrast=delta))
    return names,images,meta

def oracle(im,pre,high,strict=False):
    a=np.asarray(im,dtype=np.int32);gray=(77*a[:,:,0]+150*a[:,:,1]+29*a[:,:,2]+128)//256
    if pre==0:p=gray;radius=1
    else:
        p=np.zeros_like(gray);windows=np.lib.stride_tricks.sliding_window_view(gray,(5,5))
        if pre==1:p[2:-2,2:-2]=np.median(windows[:,:,1:4,1:4],axis=(-1,-2)).astype(np.int32)
        else:
            weights=np.array((1,4,6,4,1) if pre==2 else (1,2,1),dtype=np.int32)
            patch=windows if pre==2 else windows[:,:,1:4,1:4]
            denom=int(weights.sum()**2)
            p[2:-2,2:-2]=(np.einsum('ijkl,k,l->ij',patch,weights,weights)+denom//2)//denom
        radius=3
    gx=np.zeros_like(p);gy=np.zeros_like(p)
    gx[1:-1,1:-1]=-p[:-2,:-2]+p[:-2,2:]-2*p[1:-1,:-2]+2*p[1:-1,2:]-p[2:,:-2]+p[2:,2:]
    gy[1:-1,1:-1]=-p[:-2,:-2]-2*p[:-2,1:-1]-p[:-2,2:]+p[2:,:-2]+2*p[2:,1:-1]+p[2:,2:]
    mag=np.abs(gx)+np.abs(gy);valid=np.zeros_like(p,bool);valid[radius:-radius,radius:-radius]=True
    mag=np.where(valid,mag,0);dr=direction(gx,gy);keep=thin(mag,dr,valid,strict)
    e,c,s,d=descriptor(mag,dr,keep,high)
    return local_link(e,c,s,d)

def main():
    names,images,meta=fixtures();ctls=[];latency=6*HT+61
    with (BUILD/'e2_vectors.txt').open('w') as f:
        for im in images:
            a=np.asarray(im)
            for sy in range(H+18):
                for x in range(HT):
                    de=2<=sy<H+2 and x<W;hs=x==W+1;vs=sy==0
                    r,g,b=map(int,a[sy-2,x]) if de else (0,0,0)
                    f.write(f'{(r<<16)|(g<<8)|b:06x} {int(de)} {int(hs)} {int(vs)}\n')
                    ctls.append((int(de),int(hs),int(vs)))
        f.write('000000 0 0 0\n'*(latency+4));ctls += [(0,0,0)]*(latency+4)
    ctlref=[(0,0,0)]*(latency-1)+ctls
    variants=[('bypass58',0,58,0),('median50',1,50,0),('g3_58',3,58,0),
              ('g5_58',2,58,0),('g5_50',2,50,0),('g5_50_strict',2,50,1)]
    observed={}
    for label,pre,high,strict in variants:
        sim.run('tb_e7_image',dict(WIDTH=W,HEIGHT=H,HTOTAL=HT,HIGH=high,PRE=pre,STRICT=strict))
        pixels=[]
        for i,line in enumerate((BUILD/'e2_observed.txt').read_text().splitlines()):
            color,de,hs,vs=line.split();ctl=tuple(map(int,(de,hs,vs)))
            assert ctl==ctlref[i],('sync',label,i,ctl,ctlref[i])
            if ctl[0]:
                color=int(color,16);assert color in (0,0xffffff);pixels.append(bool(color))
        assert len(pixels)==len(images)*W*H
        masks=np.asarray(pixels,bool).reshape(len(images),H,W)
        for i,im in enumerate(images):assert np.array_equal(masks[i],oracle(im,pre,high,bool(strict))),('RTL/oracle',label,names[i])
        observed[label]=masks
        (ROOT/f'reports/e7_image_{label}.log').write_text((BUILD/'tb_e7_image_run.log').read_text())
    rows=[];sheet=Image.new('RGB',(W*(len(variants)+1),(H+24)*len(images)),(20,20,20));draw=ImageDraw.Draw(sheet)
    for i,(name,im) in enumerate(zip(names,images)):
        row=dict(name=name,**meta[i],variants={})
        panels=[('input '+name,im)]
        for label,_,_,_ in variants:
            mask=observed[label][i];metrics=topology(mask)
            if name.startswith('flat_noise'):metrics['known_flat_false_pixels']=int(mask[7:-7,7:-7].sum())
            if name.startswith('noisy_step'):
                metrics['known_boundary_rows_hit']=int(mask[7:-7,W//2-3:W//2+3].any(axis=1).sum())
                metrics['known_boundary_rows_total']=H-14
                metrics['known_flat_false_pixels']=int(mask[7:-7,7:W//2-7].sum()+mask[7:-7,W//2+7:-7].sum())
            row['variants'][label]=metrics
            panel=Image.fromarray((mask*255).astype('uint8')).convert('RGB');panels.append((label,panel))
            panel.save(OUT/f'{name}_{label}.png')
        for col,(label,panel) in enumerate(panels):
            draw.text((col*W+2,i*(H+24)+2),label,fill='white');sheet.paste(panel,(col*W,i*(H+24)+22))
        rows.append(row);im.save(OUT/f'{name}_input.png')
    sheet.save(OUT/'comparison.png')
    result=dict(status='PASS',rtl_outputs=len(images)*len(variants),fixtures=rows,variants=variants,
        latency_cycles=latency,HD_latency_cycles=6*2200+61,
        ground_truth='Only synthetic flat ROI and vertical boundary row coverage; no board frames or measured real recall',
        NMS_decision='Retain non-strict default for board candidate; inspect strict pixel thinning versus connectivity separately')
    (ROOT/'reports/e7_image_verification.json').write_text(json.dumps(result,indent=2))
    print('E7 IMAGE PASS',len(images)*len(variants),'actual RTL outputs, exact oracle and every sync token')

if __name__=='__main__':main()
