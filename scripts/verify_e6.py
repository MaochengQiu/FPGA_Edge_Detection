from pathlib import Path
from collections import deque
import hashlib, json, random
import run_tests as sim

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'sim/build_e6'; BUILD.mkdir(parents=True,exist_ok=True)
sim.BUILD=BUILD
sim.TB_RTL['tb_e6_tmds']=['rtl/dvi_tx/edge_dvi_encode.v','rtl/dvi_tx/edge_dvi_encoder.v']
TOKENS=(0b1101010100,0b0010101011,0b0101010100,0b1010101011)

def encode(value, de, ctrl, disparity):
    if not de: return TOKENS[ctrl],0
    use_xnor=value.bit_count()>4 or (value.bit_count()==4 and not value&1)
    bits=[value&1]
    for j in range(1,8): bits.append(bits[-1]^((value>>j)&1)^int(use_xnor))
    q=sum(b<<i for i,b in enumerate(bits)); flag=int(not use_xnor)
    balance=2*q.bit_count()-8
    if disparity==0 or balance==0:
        inv=1-flag
    else:
        inv=int((disparity>0 and balance>0) or (disparity<0 and balance<0))
    symbol=(inv<<9)|(flag<<8)|(q^(255 if inv else 0))
    # Independent count of transmitted ones; compare the actual signed balance.
    new_disparity=disparity+2*symbol.bit_count()-10
    # Independent inverse: verify exact original byte, including black and white.
    recovered_q=(symbol&255)^(255 if symbol&512 else 0)
    recovered=recovered_q&1
    for j in range(1,8):
        bit=((recovered_q>>j)^(recovered_q>>(j-1)))&1
        if not symbol&256: bit^=1
        recovered|=bit<<j
    assert recovered==value
    return symbol,new_disparity

def vectors():
    # Reachability rather than assuming arbitrary disparity states are legal.
    paths={0:[]};queue=deque([0])
    while queue:
        rd=queue.popleft()
        for v in range(256):
            _,dest=encode(v,1,0,rd)
            assert abs(dest)<=8,(rd,v,dest)
            if dest not in paths:
                paths[dest]=paths[rd]+[v];queue.append(dest)
    stats=dict(reachable_disparities=sorted(paths),exhaustive_state_byte_pairs=0,
               midstream_reset_cycles=0,cycles=0,active_pixels=0,control_cycles=0)
    rd=[0,0,0];pipe=deque([(0,0,0,0)]*2)
    file=BUILD/'e6_tmds_vectors.txt'
    with file.open('w') as f:
        def push(rgb=0,de=0,hs=0,vs=0,rst=0):
            delayed=pipe.popleft();pipe.append((rgb,de,hs,vs))
            data,valid,h,v=delayed
            expected=[]
            for lane in range(3):
                if rst: symbol,rd[lane]=0,0
                else: symbol,rd[lane]=encode((data>>(8*lane))&255,valid,(h|(v<<1)) if lane==0 else 0,rd[lane])
                expected.append(symbol)
            f.write(f'{rst:x} {rgb:06x} {de:x} {hs:x} {vs:x} '+
                    ' '.join(f'{x:03x}' for x in expected)+'\n')
            stats['cycles']+=1;stats['active_pixels' if de else 'control_cycles']+=1
            stats['midstream_reset_cycles']+=rst
        for _ in range(6):push(rst=1)
        for ctrl in range(4):
            for _ in range(8):push(0xabcdef,0,ctrl&1,ctrl>>1)
        for rd_value,path in paths.items():
            for v in range(256):
                for _ in range(4):push()
                for entry in path:push(entry*0x010101,1)
                push(v*0x010101,1)
                stats['exhaustive_state_byte_pairs']+=1
        for run in range(1,257):
            for _ in range(run):push(0xffffff,1)
            for _ in range(run):push(0,1)
            for _ in range(8):push()
        rng=random.Random(6001)
        for i in range(100000):
            push(rng.getrandbits(24),int(i%2200<1920),int(i%2200>=2008),int(i%1125<5),
                 int(i in (19999,20000,20001,70000,70001,70002)))
        # Actual 1080p horizontal cadence, mixed edges and changing sync polarity values.
        for y in range(32):
            for x in range(2200):
                rgb=0xffffff if (x%2 if y%2 else x%97==0) else 0
                push(rgb,int(x<1920),int(2008<=x<2052),int(y<5))
        for _ in range(8):push()
    return stats

def main():
    stats=vectors();records=[]
    tests=[('tb_e6_tmds',{}),('tb_e5_output_ab',{}),('tb_e5_controls',{}),
           ('tb_control',{}),('tb_e3_controls',{}),
           ('tb_final_hud',dict(PALETTE_PROBE=1,DVI_TRANSPORT=1)),
           ('tb_m2_starvation',{}),('tb_video_out',{})]
    for top,params in tests:
        sim.run(top,params)
        assert 'PASS' in (BUILD/(top+'_run.log')).read_text()
        records.append(dict(test=top,params=params,status='PASS'))
    result=dict(status='PASS',tests=records,tmds_vectors=stats,
        board_blackout='Not reproducible remotely; board confirmation required',
        scope='Transport encoder replacement candidate; fixed edge core and M2 pure BW retained')
    (ROOT/'reports/e6_verification.json').write_text(json.dumps(result,indent=2))
    print('E6 VERIFICATION PASS '+json.dumps(stats))

if __name__=='__main__':main()
