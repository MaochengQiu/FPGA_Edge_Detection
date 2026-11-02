from pathlib import Path
import hashlib,json,re
import run_tests as sim

ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'sim/build_g1_core'
BUILD.mkdir(parents=True,exist_ok=True);sim.BUILD=BUILD

def main():
    original=sorted((ROOT/'sim/reference/e7_resource').glob('*.sv'))
    modules=[]
    for p in original:modules+=re.findall(r'^module\s+(\w+)',p.read_text(),re.M)
    assert len(modules)==len(set(modules))==30
    names=re.compile(r'\b('+'|'.join(sorted(modules,key=len,reverse=True))+r')\b')
    refs=[]
    for p in original:
        target=BUILD/('e7_ref_'+p.name)
        target.write_text(names.sub(lambda m:'e7_ref_'+m[1],p.read_text()))
        refs.append(str(target))
    sim.TB_RTL['tb_g1_equivalence']=refs
    results=[]
    for label,params in [('all_modes_PRE',{}),('HD_banks_split',dict(WIDTH=1920,HEIGHT=24,HTOTAL=2200,FRAMES=3,HD=1))]:
        sim.run('tb_g1_equivalence',params)
        log=(BUILD/'tb_g1_equivalence_run.log').read_text();assert 'G1 CORE PASS' in log
        (ROOT/f'reports/g1_core_{label}.log').write_text(log)
        results.append(dict(test=label,params=params,status='PASS'))
    # These exercise board controls and the visible E8R version marker.
    for top,params in [('tb_e7_controls',{}),('tb_e3_controls',{}),
        ('tb_final_hud',dict(PALETTE_PROBE=1,DVI_TRANSPORT=1,QUALITY_FILTER=1,RESOURCE_OPT=1)),
        ('tb_m2_starvation',{}),('tb_video_out',{})]:
        sim.run(top,params)
        assert 'PASS' in (BUILD/(top+'_run.log')).read_text()
        results.append(dict(test=top,params=params,status='PASS'))
    report=dict(status='PASS',tests=results,reference='Frozen complete E7 edge RTL, namespaced only for dual-core simulation',
        identical='Every RGB/DE/HS/VS/debug magnitude/debug edge/input SOF cycle, 8 pages x 4 PRE plus actual 1920-wide bank/split exercise',
        startup_gamma='Verified separately; old undefined first-load RGB is not treated as a defined value')
    (ROOT/'reports/g1_core_verification.json').write_text(json.dumps(report,indent=2))
    print('G1 CORE VERIFICATION PASS:',len(results),'configurations')

if __name__=='__main__':main()
