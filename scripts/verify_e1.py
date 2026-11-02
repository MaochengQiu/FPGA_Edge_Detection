"""Independent integer NMS oracle, RTL A/B fixtures, and unmerged CPU tracing.
No human annotations or real-board quality measurements are invented.
"""
from pathlib import Path
import collections,hashlib,json,math,os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parents[1]/'tools/python_libs'))
import numpy as np
from PIL import Image,ImageDraw,ImageFont,ImageFilter
import run_tests as sim
BUILD=ROOT/'sim/build';INPUT=ROOT/'reference/e1_inputs';OUTPUT=ROOT/'reports/e1_ab'
INPUT.mkdir(exist_ok=True);OUTPUT.mkdir(exist_ok=True)
PAIRS=((-1,0,1,0),(-1,-1,1,1),(0,-1,0,1),(1,-1,-1,1))

def direction(gx,gy):
    ax=np.abs(gx);ay=np.abs(gy)
    return np.where(ay*1024<=ax*424,0,np.where(ax*1024<=ay*424,2,np.where((gx<0)^(gy<0),3,1))).astype(np.uint8)

def thin(mag,dr,valid,strict=False):
    h,w=mag.shape;keep=np.zeros((h,w),bool)
    for y in range(1,h-1):
        for x in range(1,w-1):
            ax,ay,bx,by=PAIRS[int(dr[y,x])]
            c=mag[y,x];a=mag[y+ay,x+ax];b=mag[y+by,x+bx]
            keep[y,x]=valid[y,x] and valid[y+ay,x+ax] and valid[y+by,x+bx] and c>0 and c>=a and (c>b if strict else c>=b and (c>a or c>b))
    return keep

def sobel(rgb):
    a=np.asarray(rgb,dtype=np.int32)
    gray=(77*a[:,:,0]+150*a[:,:,1]+29*a[:,:,2]+128)//256
    gx=np.zeros_like(gray);gy=gx.copy();valid=np.zeros_like(gray,dtype=bool)
    p=gray
    gx[1:-1,1:-1]=-p[:-2,:-2]+p[:-2,2:]-2*p[1:-1,:-2]+2*p[1:-1,2:]-p[2:,:-2]+p[2:,2:]
    gy[1:-1,1:-1]=-p[:-2,:-2]-2*p[:-2,1:-1]-p[:-2,2:]+p[2:,:-2]+2*p[2:,1:-1]+p[2:,2:]
    valid[1:-1,1:-1]=True
    mag=np.abs(gx)+np.abs(gy);dr=direction(gx,gy)
    return mag,dr,valid,thin(mag,dr,valid)

def nms_units():
    results=[];rng=np.random.default_rng(431)
    for w,h,ht,strict in [(w,h,ht,s) for w,h,ht in ((1,1,5),(2,2,6),(3,3,8),(9,7,14),(32,16,40),(1920,8,2200),(8,1080,12)) for s in (0,1)]:
        vectors=[];expected=[]
        for frame in range(10):
            yy,xx=np.indices((h,w));mag=rng.integers(0,1531,size=(h,w),dtype=np.int32)
            dr=np.full((h,w),frame%4,dtype=np.uint8);valid=np.ones((h,w),bool)
            if frame<4:mag[:]=320 # all-equal plateau must not become thick lines
            elif frame<8:
                mag=np.where((xx==w//2)|(yy==h//2),1020,300).astype(np.int32)
            else:
                dr=rng.integers(0,4,size=(h,w),dtype=np.uint8);valid=rng.random((h,w))>.12
            keep=thin(mag,dr,valid,bool(strict))
            for sy in range(h+10):
                for x in range(ht):
                    de=2<=sy<h+2 and x<w;y=sy-2
                    ctl=int(de)|(int(x==w+1)<<1)|(int(sy==0)<<2)|(int(de and x==0 and y==0)<<3)
                    m=int(mag[y,x]) if de else 0;d=int(dr[y,x]) if de else 0;v=int(valid[y,x]) if de else 0
                    vectors.append((m,d,v,ctl))
                    k=int(keep[y,x]) if de else 0;expected.append((k,m if k else 0,ctl))
        delay=ht+5
        vectors += [(0,0,0,0)]*(delay+4);expected += [(0,0,0)]*(delay+4)
        (BUILD/'nms_vectors.txt').write_text(''.join('%d %d %d %d\n'%v for v in vectors))
        sim.run('tb_nms',{'WIDTH':w,'HEIGHT':h,'HTOTAL':ht,'STRICT_TIES':strict})
        observed=[tuple(map(int,s.split())) for s in (BUILD/'nms_observed.txt').read_text().splitlines()]
        reference=[(0,0,0)]*(delay-1)+expected
        for i,v in enumerate(observed):assert v==reference[i],('NMS',w,h,i,v,reference[i])
        results.append(dict(width=w,height=h,htotal=ht,strict_ties=strict,samples=len(observed),status='PASS'))
    return results

def directions():
    pairs=set((x,y) for x in (0,-1,1,-1020,1020) for y in (0,-1,1,-1020,1020))
    for a in range(1,1021):
        for b in (int(a*math.tan(math.pi/8)),int(a/math.tan(math.pi/8))):
            for delta in (-1,0,1):
                if 0<=b+delta<=1020:
                    for sx,sy in ((1,1),(-1,1),(1,-1),(-1,-1)):
                        pairs.add((sx*a,sy*(b+delta)))
    vectors=[];quantization=0;worst=0.
    for gx,gy in sorted(pairs):
        d=int(direction(np.array(gx),np.array(gy)));vectors.append((gx,gy,d))
        angle=math.degrees(math.atan2(gy,gx))%180 if gx or gy else 0
        ideal=int((angle+22.5)//45)%4
        if d!=ideal:
            distance=min(abs(angle-b) for b in (22.5,67.5,112.5,157.5))
            assert distance<.02,(gx,gy,angle,d,ideal)
            quantization+=1;worst=max(worst,distance)
    (BUILD/'direction_vectors.txt').write_text(''.join('%d %d %d\n'%v for v in vectors))
    sim.run('tb_direction')
    # Sobel extrema over the binary vertices (linear gradient, convex L1).
    from itertools import product
    gradients=[sim.grad(p) for p in product((0,255),repeat=9)]
    assert max(abs(g[0]) for g in gradients)==1020
    assert max(abs(g[1]) for g in gradients)==1020
    assert max(g[2] for g in gradients)==1530
    return dict(status='PASS',vectors=len(vectors),fixed_point_boundary_differences=quantization,
        maximum_boundary_difference_deg=worst,gx_gy_abs_max=1020,l1_attainable_max=1530,
        signed_bits=11,magnitude_bits=11,display_only_clip=255)

def fixtures():
    w,h=256,192;rng=np.random.default_rng(20261031);images=[];metadata=[]
    def add(name,im,kind,detail):
        p=INPUT/(name+'.png')
        if not p.exists():im.convert('RGB').save(p)
        images.append(Image.open(p).convert('RGB'))
        metadata.append(dict(name=name,kind=kind,detail=detail,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
    y,x=np.indices((h,w));a=np.where((x//16+y//16)%2,180,40);a[:,128:]=np.where((x[:,128:]//16+y[:,128:]//16)%2,72,64)
    a=np.clip(a+rng.integers(-1,2,size=a.shape),0,255).astype('uint8')
    add('checker',Image.fromarray(a),'synthetic','high/low contrast checker + fixed low amplitude noise')
    im=Image.new('RGB',(w,h),(65,65,65));d=ImageDraw.Draw(im)
    d.polygon([(55,20),(201,20),(180,170),(76,170)],fill=(130,125,112),outline=(170,168,160),width=2)
    for yy in range(40,155,18):
        d.line([(70,yy),(95,yy-7),(120,yy+5),(145,yy-7),(185,yy)],fill=(142,136,122),width=2)
    add('cup_pattern',im,'synthetic','cup silhouette and low contrast motif; not a real paper-cup photograph')
    font_path=Path(r'C:\Windows\Fonts\arial.ttf')
    font=ImageFont.truetype(str(font_path),23) if font_path.exists() else ImageFont.load_default()
    im=Image.new('RGB',(w,h),(64,64,64));d=ImageDraw.Draw(im)
    for i,s in enumerate(('FPGA Sobel','0123456789','edge / PCB','weak detail')):
        v=180 if i<2 else 77;d.text((8,8+i*43),s,font=font,fill=(v,v,v),stroke_width=0)
    add('printed_text',im,'synthetic','rasterized printed text with strong/weak contrast')
    im=Image.new('RGB',(w,h),(32,54,40));d=ImageDraw.Draw(im)
    for i in range(5):
        yy=20+i*32;v=92 if i<2 else 64
        d.line([(14,yy),(70+i*8,yy),(100+i*8,yy+16),(235,yy+16)],fill=(45,v,48),width=2+i%2)
        for xx in (14,235):d.ellipse((xx-5,yy-5,xx+5,yy+5),outline=(110,120,75),width=2)
    add('pcb_tracks',im,'synthetic','thin PCB-like tracks and vias; not a measured PCB photograph')
    photo=INPUT/'astronaut_source.png'
    assert hashlib.sha256(photo.read_bytes()).hexdigest()=='88431cd9653ccd539741b555fb0a46b61558b301d4110412b5bc28b5e3ea6cb5','Unexpected official astronaut source'
    face=Image.open(photo).convert('RGB').crop((150,50,300,200)).resize((w,h),Image.Resampling.LANCZOS)
    add('face_photo',face,'public_real_photo','scikit-image v0.25.2 astronaut.png, NASA public-domain portrait, fixed crop (150,50,300,200); not an E1 hardware capture')
    step=Image.fromarray(np.where(x<128,48,144).astype('uint8')).filter(ImageFilter.GaussianBlur(2))
    add('blurred_step',step,'synthetic_known_boundary','analytic source boundary x=127.5; sigma=2 blur before quantization')
    for i in range(3):
        im=Image.new('RGB',(w,h),(45,45,45));d=ImageDraw.Draw(im);xx=45+8*i
        d.rectangle((xx,45,xx+100,140),fill=(86,86,86));d.ellipse((xx+25,65,xx+75,115),outline=(98,98,98),width=2)
        add('motion_%d'%i,im,'synthetic_sequence','8-pixel translation per frame; no measured sensor motion/latency')
    (INPUT/'fixtures.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    return images,metadata

def topology(mask):
    h,w=mask.shape;nb=np.zeros_like(mask,dtype=np.uint8)
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            if dx or dy:nb[1:-1,1:-1]+=mask[1+dy:h-1+dy,1+dx:w-1+dx]
    visited=np.zeros_like(mask);sizes=[]
    for y,x in zip(*np.nonzero(mask)):
        if visited[y,x]:continue
        stack=[(y,x)];visited[y,x]=1;n=0
        while stack:
            yy,xx=stack.pop();n+=1
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    ny,nx=yy+dy,xx+dx
                    if (dx or dy) and 0<=ny<h and 0<=nx<w and mask[ny,nx] and not visited[ny,nx]:
                        visited[ny,nx]=1;stack.append((ny,nx))
        sizes.append(n)
    blocks=mask[:-1,:-1]&mask[1:,:-1]&mask[:-1,1:]&mask[1:,1:]
    return dict(edge_pixels=int(mask.sum()),solid_2x2=int(blocks.sum()),components_8=len(sizes),
        isolated_pixels=sum(s==1 for s in sizes),endpoints_8=int((mask&(nb==1)).sum()))

def hysteresis(mag,low,high):
    allowed=mag>=low;out=mag>=high;q=collections.deque(zip(*np.nonzero(out)));h,w=mag.shape
    while q:
        y,x=q.popleft()
        for dy in (-1,0,1):
            for dx in (-1,0,1):
                yy,xx=y+dy,x+dx
                if 0<=yy<h and 0<=xx<w and allowed[yy,xx] and not out[yy,xx]:out[yy,xx]=1;q.append((yy,xx))
    return out

def image_ab():
    images,meta=fixtures();w,h=images[0].size;ht=w+32;L=3*ht+27
    references=[sobel(im) for im in images];vectors=[];ctl_reference=[]
    with (BUILD/'e1_vectors.txt').open('w') as f:
        for im in images:
            a=np.array(im)
            for sy in range(h+12):
                for x in range(ht):
                    de=2<=sy<h+2 and x<w;hs=x==w+1;vs=sy==0
                    r,g,b=map(int,a[sy-2,x]) if de else (0,0,0)
                    f.write(f'{(r<<16)|(g<<8)|b:06x} {int(de)} {int(hs)} {int(vs)}\n')
                    ctl_reference.append((int(de),int(hs),int(vs)))
        f.write('000000 0 0 0\n'*(L+4));ctl_reference += [(0,0,0)]*(L+4)
    expected_ctl=[(0,0,0)]*(L-1)+ctl_reference
    observed=[]
    for enabled in (0,1):
        sim.run('tb_e1_image',{'WIDTH':w,'HEIGHT':h,'HTOTAL':ht,'NMS_ENABLE':enabled})
        pixels=[]
        with (BUILD/'e1_observed.txt').open() as f:
            for i,line in enumerate(f):
                color,de,hs,vs=line.split();ctl=tuple(map(int,(de,hs,vs)))
                assert ctl==expected_ctl[i],('image sync',enabled,i,ctl,expected_ctl[i])
                if ctl[0]:
                    c=int(color,16);assert c in (0,0xffffff);pixels.append(c!=0)
        assert len(pixels)==len(images)*w*h
        observed.append(np.array(pixels,dtype=bool).reshape(len(images),h,w))
        (ROOT/f'reports/e1_images_nms{enabled}.log').write_text((BUILD/'tb_e1_image_run.log').read_text())
    rows=[];sheet=Image.new('RGB',(w*4,(h+36)*len(images)),(20,20,20));draw=ImageDraw.Draw(sheet)
    for i,(im,info,ref) in enumerate(zip(images,meta,references)):
        mag,dr,valid,keep=ref;raw=valid&(mag>=24);nms=raw&keep
        assert np.array_equal(observed[0][i],raw),('Sobel oracle',info['name'])
        assert np.array_equal(observed[1][i],nms),('NMS oracle',info['name'])
        assert not np.any(nms&~raw)
        offline=hysteresis(np.where(keep,mag,0),12,24)
        row=dict(name=info['name'],kind=info['kind'],threshold=24,sobel=topology(raw),nms=topology(nms),
            offline_strict_tie_nms=topology(thin(mag,dr,valid,True)&raw),
            offline_cpu_hysteresis_pixels=int(offline.sum()),precision_recall_f1='NOT REPORTED: no manual ground truth')
        if info['name']=='blurred_step':
            row['known_step_mean_x_error_px']={k:float(np.abs(np.nonzero(mask)[1]-127.5).mean()) for k,mask in [('sobel',raw),('nms',nms)]}
        rows.append(row)
        yy=i*(h+36);panels=[im,Image.fromarray(np.minimum(mag,255).astype('uint8')).convert('RGB'),
            Image.fromarray((observed[0][i]*255).astype('uint8')).convert('RGB'),Image.fromarray((observed[1][i]*255).astype('uint8')).convert('RGB')]
        for j,p in enumerate(panels):
            label=(info['name']+' ['+info['kind']+']') if j==0 else ('M5 gradient','Sobel T=24','NMS T=24')[j-1]
            draw.text((j*w+4,yy+3),label,fill='white');sheet.paste(p,(j*w,yy+32))
        for label,p in zip(('input','gradient','sobel','nms'),panels):p.save(OUTPUT/(info['name']+'_'+label+'.png'))
    sheet.save(OUTPUT/'comparison.png')
    # Correct connectivity must traverse a long weak chain and discard a
    # disconnected weak island. A one-hop neighborhood of strong is insufficient.
    chain=np.zeros((9,16),np.int32);chain[4,2]=40;chain[4,3:12]=16;chain[1,12:15]=16
    connected=hysteresis(chain,12,24)
    assert connected[4,2:12].all() and not connected[1,12:15].any()
    return dict(status='PASS',fixtures=rows,rtl_images=len(images)*2,latency_cycles=L,
        added_latency_1080p_us=2205/148.5,threshold='24 unchanged for both branches',
        figures='e1_ab/comparison.png',hysteresis='CPU 8-connected flood fill only; not merged in RTL',
        chain_test='PASS: 9 weak samples connected to strong; disconnected weak island rejected')

if __name__=='__main__':
    report=dict(direction=directions(),nms_unit=nms_units(),image_ab=image_ab())
    (ROOT/'reports/e1_algorithm_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('E1 ALGORITHM PASS: direction, NMS/borders/plateaus, actual RTL fixed-image A/B, unchanged M5 by equivalence; CPU-only connectivity experiment')
