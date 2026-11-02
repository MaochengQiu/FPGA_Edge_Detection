"""E2 local-graph verification, including known failures of global tracing."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parents[1]/'tools/python_libs'))
import numpy as np
import run_tests as sim
from e2_model import local_link
BUILD=ROOT/'sim/build';BUILD.mkdir(exist_ok=True)

def unit_suite():
    rng=np.random.default_rng(25050);results=[]
    for w,h,ht,bridge in [(w,h,ht,b) for w,h,ht in ((1,1,5),(2,3,6),(5,5,9),(16,12,22),(32,20,40),(1920,8,2200),(8,1080,12)) for b in (0,1)]:
        vectors=[];expected=[]
        for frame in range(10):
            a=np.zeros((h,w),bool);c=a.copy();s=a.copy();dr=np.full((h,w),2,dtype=np.uint8)
            if frame==1:a[:]=1;c[:]=1 # all-weak frame, no seeds
            if frame==2 and h>4 and w>4:a[h//2,w//2]=1;c[:]=a;s[:]=a
            if frame==3 and h>4 and w>5:
                a[h//2,w//2-1:w//2+1]=1;c[:]=a;s[:]=a
            if frame in (4,5,6) and h>4 and w>8:
                yy=h//2;a[yy,2:w-2]=1;c[:]=a;s[:]=a
                c[yy,w//2]=0;s[yy,w//2-1:w//2+2]=0
                if frame==5:a[yy,w//2]=0 # no raw support: bridge forbidden
                if frame==6:dr[:]=0 # wrong normal for a horizontal gap
            if frame in (7,8):
                a=rng.random((h,w))>.5;c=a&(rng.random((h,w))>.4);s=c&(rng.random((h,w))>.5)
                dr=rng.integers(0,4,size=(h,w),dtype=np.uint8)
            out=local_link(a,c,s,dr,bridge=bool(bridge))
            desc=(dr.astype(np.uint8)<<3)|(s.astype(np.uint8)<<2)|(c.astype(np.uint8)<<1)|a.astype(np.uint8)
            for sy in range(h+16):
                for x in range(ht):
                    de=2<=sy<h+2 and x<w;y=sy-2
                    ctl=int(de)|(int(x==w+1)<<1)|(int(sy==0)<<2)|(int(de and x==0 and y==0)<<3)
                    vectors.append((int(desc[y,x]) if de else 0,ctl));expected.append((int(out[y,x]) if de else 0,ctl))
        delay=2*ht+32;vectors += [(0,0)]*(delay+4);expected += [(0,0)]*(delay+4)
        (BUILD/'link_vectors.txt').write_text(''.join('%d %d\n'%v for v in vectors))
        sim.run('tb_local_link',{'WIDTH':w,'HEIGHT':h,'HTOTAL':ht,'BRIDGE_ENABLE':bridge})
        obs=[tuple(map(int,s.split())) for s in (BUILD/'link_observed.txt').read_text().splitlines()]
        ref=[(0,0)]*(delay-1)+expected
        for i,v in enumerate(obs):assert v==ref[i],('link oracle',w,h,bridge,i,v,ref[i])
        results.append(dict(width=w,height=h,bridge=bridge,samples=len(obs),status='PASS'))
    return results

def directed_model_checks():
    a=np.zeros((11,25),bool);c=a.copy();s=a.copy();d=np.full(a.shape,2,dtype=np.uint8)
    a[5,3:18]=1;c[:]=a;s[5,3:7]=1;s[5,9:18]=1;c[5,8]=0
    out=local_link(a,c,s,d)
    assert out[5,7:11].all(),'supported weak gap not restored'
    a[5,8]=0;out=local_link(a,c,s,d);assert not out[5,8],'zero-gradient gap was invented'
    a[:]=0;c[:]=0;s[:]=0;a[5,3:22]=1;c[:]=a;s[5,3:6]=1
    out=local_link(a,c,s,d);assert not out[5,15],'local graph falsely claimed long-range hysteresis'
    for n in (1,2):
        a[:]=0;c[:]=0;s[:]=0;a[5,10:10+n]=1;c[:]=a;s[:]=a
        assert not local_link(a,c,s,d).any(),'short strong noise retained'
    return dict(status='PASS',supported_weak_gap='restored',zero_gradient_gap='not invented',isolated_1_2='removed',
        long_weak_chain='limited as designed; not full-image hysteresis')

if __name__=='__main__':
    report=dict(directed=directed_model_checks(),units=unit_suite())
    (ROOT/'reports/e2_local_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('E2 LOCAL VERIFICATION PASS: exact bounded graph, seed support, raw-supported bridge, no wrapping/frame leakage')
