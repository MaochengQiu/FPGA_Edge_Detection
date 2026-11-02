#!/usr/bin/env python3
"""Portable regression: standard Python + Icarus or ModelSim/Questa.
Run from anywhere. RTL_SIM=modelsim selects ModelSim; MODELSIM_BIN may name
its win64/bin directory. IVERILOG and VVP may name absolute executables.
"""
from pathlib import Path
import itertools,json,os,random,re,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'sim'/'build';BUILD.mkdir(parents=True,exist_ok=True)
IVERILOG=os.environ.get('IVERILOG','iverilog');VVP=os.environ.get('VVP','vvp')
MODEL_BIN=Path(os.environ.get('MODELSIM_BIN',r'C:\modeltech64_10.5\win64'))
BACKEND=os.environ.get('RTL_SIM','iverilog' if shutil.which(IVERILOG) else 'modelsim')
MODEL_WORK=BUILD/'modelsim'/'work'
RTL=sorted((ROOT/'rtl/edge').glob('*/*.sv'))
TB_RTL={'tb_debayer_color':[
    'rtl/debayer/debayer_top_2to1.v','rtl/debayer/rgb_gain_v1.v',
    'rtl/debayer/line_buffer.v','rtl/debayer/raw_to_rgb.v','rtl/true_dual_port_ram.v']}
results=[]
def run(top,params=None):
    extra=[ROOT/p for p in TB_RTL.get(top,[])]
    if BACKEND=='modelsim':
        if not MODEL_WORK.exists():
            MODEL_WORK.parent.mkdir(parents=True,exist_ok=True)
            subprocess.run([str(MODEL_BIN/'vlib.exe'),str(MODEL_WORK)],cwd=BUILD,check=True,capture_output=True)
        command=[str(MODEL_BIN/'vlog.exe'),'-sv','-work',str(MODEL_WORK)]
        command+=list(map(str,RTL+extra))+[str(ROOT/'sim'/(top+'.sv'))]
        c=subprocess.run(command,cwd=BUILD,text=True,capture_output=True,timeout=120)
        (BUILD/(top+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8')
        if c.returncode:raise RuntimeError(c.stdout+c.stderr)
        command=[str(MODEL_BIN/'vsim.exe'),'-c','-onfinish','stop','-lib',str(MODEL_WORK),
                 '-do','onerror {quit -force -code 1}; run -all; quit -force -code 0',top]
        for k,v in (params or {}).items():command+=[f'-g{k}={v}']
        c=subprocess.run(command,cwd=BUILD,text=True,capture_output=True,timeout=180)
        (BUILD/(top+'_run.log')).write_text(c.stdout+c.stderr,encoding='utf-8')
        if c.returncode or re.search(r'\*\*\s+(?:Fatal|Error):',c.stdout+c.stderr):
            raise RuntimeError(c.stdout+c.stderr)
        print('\n'.join(line for line in c.stdout.splitlines() if 'PASS' in line))
        return
    command=[IVERILOG,'-g2012','-Wall','-s',top,'-o',str(BUILD/(top+'.vvp'))]
    for k,v in (params or {}).items():command+=['-P',f'{top}.{k}={v}']
    command += list(map(str,RTL+extra))+[str(ROOT/'sim'/(top+'.sv'))]
    c=subprocess.run(command,cwd=BUILD,text=True,capture_output=True)
    (BUILD/(top+'_compile.log')).write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stdout+c.stderr)
    c=subprocess.run([VVP,str(BUILD/(top+'.vvp'))],cwd=BUILD,text=True,capture_output=True)
    (BUILD/(top+'_run.log')).write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stdout+c.stderr)
    print(c.stdout.strip())
def gray(rgb):return (77*rgb[0]+150*rgb[1]+29*rgb[2]+128)>>8
def grad(p):
    x=-p[0]+p[2]-2*p[3]+2*p[5]-p[6]+p[8]
    y=-p[0]-2*p[1]-p[2]+p[6]+2*p[7]+p[8]
    return x,y,abs(x)+abs(y)
def gaussian(p):return (sum(a*b for a,b in zip(p,(1,2,1,2,4,2,1,2,1)))+8)>>4
def operators():
    # Exhaustive binary windows; all distinct permutations verify the Python
    # network itself, while the exact generated RTL network is simulated below.
    rng=random.Random(7)
    patterns=list(itertools.product((0,255),repeat=9))
    patterns += [tuple(rng.randrange(256) for _ in range(9)) for _ in range(3000)]
    patterns += [(0,1,2,3,5,6,4,7,8),(255,)*9,(0,)*9]
    def network(v):
        a=list(v)
        for stage in range(9):
            b=a.copy()
            for j in range(stage%2,8,2):b[j],b[j+1]=sorted((a[j],a[j+1]))
            a=b
        return a[4]
    for v in itertools.permutations(range(9)):assert network(v)==4
    padded=patterns+[(0,)*9]*12
    (BUILD/'operator_input.txt').write_text(''.join(f'{sum(p<<(8*j) for j,p in enumerate(v)):018x}\n' for v in padded))
    run('tb_operators')
    obs=[list(map(int,s.split())) for s in (BUILD/'operator_output.txt').read_text().splitlines()]
    for i,p in enumerate(patterns):
        x,y,m=grad(p)
        assert obs[i+8][0]==sorted(p)[4],('median',i,p,obs[i+8])
        assert obs[i][1]==gaussian(p),('gaussian',i,p,obs[i])
        assert obs[i+3][2:]==[x,y,m],('sobel',i,p,obs[i+3],[x,y,m])
    results.append({'test':'operators','rtl_windows':len(patterns),'median_distinct_permutations':362880,'status':'PASS'})
def pipeline(w,h,ht,extended=False):
    rng=random.Random(13+w);stim=[];expect=[];frame_count=0
    for mode in range(4):
        for display in (range(6) if not extended else (0,2,4)):
            for pattern in (('black','white','step','checker','impulse','random') if not extended else ('random',)):
                image=[]
                for y in range(h):
                    row=[]
                    for x in range(w):
                        if pattern=='black':rgb=(0,0,0)
                        elif pattern=='white':rgb=(255,255,255)
                        elif pattern=='step':rgb=(255,255,255) if x>=w//2 else (0,0,0)
                        elif pattern=='checker':rgb=(255,255,255) if (x+y)%2 else (0,0,0)
                        elif pattern=='impulse':rgb=(255,255,255) if (x,y)==(w//2,h//2) else (0,0,0)
                        else:rgb=tuple(rng.randrange(256) for _ in range(3))
                        row.append(rgb)
                    image.append(row)
                raw=[[gray(p) for p in row] for row in image]
                pre=[row.copy() for row in raw] if mode==0 else [[0]*w for _ in range(h)]
                if mode:
                    for y in range(1,h-1):
                        for x in range(1,w-1):
                            p=[raw[yy][xx] for yy in range(y-1,y+2) for xx in range(x-1,x+2)]
                            mean=gaussian(p)
                            pre[y][x]=(sorted(p)[4] if mode==1 else
                                mean if mode==2 else
                                max(0,min(255,3*raw[y][x]-2*mean)))
                threshold=(0,1,255,1020,1530,2047)[frame_count%6]
                radius=1 if mode==0 else 2
                def edge_at(px,py):
                    if px<radius or px>=w-radius or py<radius or py>=h-radius:
                        return 0
                    patch=[pre[yy][xx] for yy in range(py-1,py+2) for xx in range(px-1,px+2)]
                    return int(grad(patch)[2]>=threshold)
                for sy in range(h+10):
                    for x in range(ht):
                        de=int(2<=sy<h+2 and x<w);hs=int(x==w+1);vs=int(sy==0)
                        rgb=image[sy-2][x] if de else (0,0,0)
                        color=(rgb[0]<<16)|(rgb[1]<<8)|rgb[2]
                        stim.append((color,de,hs,vs,mode,display,threshold))
                        selected=0
                        if de:
                            y=sy-2;mag=0;edge=0
                            if radius<=x<w-radius and radius<=y<h-radius:
                                p=[pre[yy][xx] for yy in range(y-1,y+2) for xx in range(x-1,x+2)]
                                mag=grad(p)[2];edge=int(mag>=threshold)
                            gray24=raw[y][x]*0x010101
                            # Display 3 mirrors the entire previous source line
                            # into two half-width views with 2:1 horizontal sampling.
                            # It is not the old left-half/right-half wipe.
                            half=(w+1)//2
                            src_x=2*(x if x<half else x-half)
                            mirrored=0
                            if y>0:
                                if x<half:
                                    r0,g0,b0=image[y-1][src_x]
                                    mirrored=(r0<<16)|(g0<<8)|b0
                                else:
                                    mirrored=0xffffff if edge_at(src_x,y-1) else 0
                            selected=[color,gray24,0xffffff if edge else 0,
                                      mirrored,
                                      0xff3020 if edge else color,min(255,mag)*0x010101][display]
                        expect.append((selected,de,hs,vs))
                frame_count+=1
    # Flush latency; source configuration must remain its last committed frame snapshot.
    latency=2*ht+22
    stim += [(0,0,0,0,mode,display,threshold)]*(latency+4)
    expect += [(0,0,0,0)]*(latency+4)
    (BUILD/'stimulus.txt').write_text(''.join(f'{s[0]:06x} '+ ' '.join(map(str,s[1:]))+'\n' for s in stim))
    run('tb_pipeline',{'WIDTH':w,'HEIGHT':h,'HTOTAL':ht})
    obs=[]
    for s in (BUILD/'observed.txt').read_text().splitlines():
        a,b,c,d=s.split();obs.append((int(a,16),int(b),int(c),int(d)))
    expected=[(0,0,0,0)]*(latency-1)+expect
    for i,o in enumerate(obs):
        assert o==expected[i],('pipeline',w,h,'sample',i,'observed',o,'expected',expected[i])
    results.append({'test':'pipeline','width':w,'height':h,'h_total':ht,'frames':frame_count,'samples':len(obs),'status':'PASS'})
if __name__=='__main__':
    if len(sys.argv)>1:
        for top in sys.argv[1:]:run(top)
        sys.exit(0)
    operators()
    for dims in [(8,6,12),(3,3,8),(2,2,6),(1,1,5),(17,9,23)]:pipeline(*dims)
    pipeline(1920,8,2200,extended=True)
    pipeline(8,1080,12,extended=True)
    # Verify mirrored full-frame side-by-side scanlines (including odd widths).
    run('tb_composer_mirror',{'WIDTH':8,'HEIGHT':5})
    run('tb_composer_mirror',{'WIDTH':7,'HEIGHT':5})
    results.append({'test':'composer_full_frame_side_by_side','status':'PASS'})
    # Subsystem regressions include camera/AXI/display clocks and stalls.
    for top in ('tb_debayer_color','tb_color_precision','tb_color_pipeline','tb_video_health','tb_control','tb_control_white_balance','tb_threshold_limits','tb_weak_edges','tb_white_balance','tb_rgb_statistics','tb_diag_overlay','tb_final_hud','tb_frame_manager','tb_async_fifo','tb_frame_store','tb_axi_writer_throughput','tb_axi_reader_pending','tb_video_out','tb_mode_threshold_sync'):
        if (ROOT/'sim'/(top+'.sv')).exists():
            run(top);results.append({'test':top,'status':'PASS'})
    run('tb_frame_store',{'CAM_VS_LEVEL':1})
    results.append({'test':'frame_store_generic_CSI_VS_level','status':'PASS'})
    (ROOT/'reports'/'verification.json').write_text(json.dumps(results,indent=2))
    print('ALL REGRESSIONS PASSED')
