"""E3 descriptor RTL/oracle checks. Fixed seeds; no board quality claims."""
from pathlib import Path
import json
import numpy as np
import run_tests as sim
from e3_model import e3_link

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'sim/build_e3_local'
BUILD.mkdir(parents=True, exist_ok=True)
sim.BUILD = BUILD


def cases(h, w):
    rng = np.random.default_rng(33068 + w + h)
    for kind in range(16):
        a = np.zeros((h, w), bool); c = a.copy(); s = a.copy()
        d = np.full((h, w), 2, np.uint8)
        if kind < 12 and h >= 7 and w >= 7:
            cx, cy = w // 2, h // 2
            dx, dy, normal = ((1,0,2),(0,1,0),(1,1,3),(1,-1,1))[kind % 4]
            for k in range(-2, 3):
                yy, xx = cy + k*dy, cx + k*dx
                a[yy,xx] = c[yy,xx] = True; d[yy,xx] = normal
            if kind < 8: s[cy-2*dy,cx-2*dx] = True
            if kind in (4,5): c[cy,cx] = False  # supplement cannot invent missing candidates
            if kind in (6,7): d[cy,cx] = (normal+2) % 4
        elif kind == 12:
            a[:] = c[:] = True  # no seed, including old-frame leakage check
        elif kind in (13,14):
            a = rng.random((h,w)) > .35
            c = a & (rng.random((h,w)) > .25)
            s = c & (rng.random((h,w)) > .8)
            d = rng.integers(0,4,(h,w),dtype=np.uint8)
        yield kind, a, c, s, d


def main():
    records=[]
    for w,h,ht in ((1,1,5),(2,3,6),(5,5,9),(16,12,22),(32,20,40),(1920,8,2200),(8,1080,12)):
        for enabled in (0,1):
            vectors=[]; expect=[]
            for kind,a,c,s,d in cases(h,w):
                out=e3_link(a,c,s,d,enabled=bool(enabled))
                if enabled and kind < 4 and h>=7 and w>=7:
                    assert out[h//2,w//2], ('seeded tangent not recovered',kind)
                if kind in (8,9,10,11,12): assert not out.any(), ('unseeded leakage',kind)
                desc=(d<<3)|(s.astype(np.uint8)<<2)|(c.astype(np.uint8)<<1)|a.astype(np.uint8)
                for sy in range(h+16):
                    for x in range(ht):
                        de=2<=sy<h+2 and x<w; y=sy-2
                        ctl=int(de)|(int(x==w+1)<<1)|(int(sy==0)<<2)|(int(de and x==0 and y==0)<<3)
                        vectors.append((int(desc[y,x]) if de else 0,ctl))
                        expect.append((int(out[y,x]) if de else 0,ctl))
            delay=2*ht+32
            vectors += [(0,0)]*(delay+4); expect += [(0,0)]*(delay+4)
            (BUILD/'link_vectors.txt').write_text(''.join('%d %d\n'%v for v in vectors))
            sim.run('tb_local_link',{'WIDTH':w,'HEIGHT':h,'HTOTAL':ht,'WEAK_CHAIN_ENABLE':enabled})
            ref=[(0,0)]*(delay-1)+expect
            count=0
            for i,line in enumerate((BUILD/'link_observed.txt').read_text().splitlines()):
                actual=tuple(map(int,line.split()))
                assert actual==ref[i],(w,h,enabled,i,actual,ref[i]);count+=1
            records.append(dict(width=w,height=h,enabled=enabled,samples=count,status='PASS'))
    report=dict(status='PASS',cases=records,limits='5x5, straight five original NMS points, >=1 high seed; no global tracing')
    (ROOT/'reports/e3_local_verification.json').write_text(json.dumps(report,indent=2))
    print('E3 LOCAL PASS',len(records),'configurations',sum(r['samples'] for r in records),'clocks')


if __name__=='__main__':main()
