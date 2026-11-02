from pathlib import Path
import json
import run_tests as sim

ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'sim/build_e7'
BUILD.mkdir(parents=True,exist_ok=True);sim.BUILD=BUILD

def main():
    p=ROOT/'sim/tb_e7_output_ab.sv'
    text=(ROOT/'sim/tb_e5_output_ab.sv').read_text().replace('tb_e5_output_ab','tb_e7_output_ab')
    text=text.replace('L=5*HT+60','L=6*HT+61').replace('.LINK_ENABLE(1))','.LINK_ENABLE(1),.QUALITY_FILTER_ENABLE(1))').replace('E5 OUTPUT','E7 OUTPUT')
    p.write_text(text)
    p=ROOT/'sim/tb_e7_controls.sv'
    text=(ROOT/'sim/tb_e5_controls.sv').read_text().replace('tb_e5_controls','tb_e7_controls')
    text=text.replace('.DISPLAY_MAX(7))','.DISPLAY_MAX(7),.PREPROCESS_DEFAULT(2),.THRESHOLD_DEFAULT(50))')
    text=text.replace('write_cfg(0,58);','if(pre!=2 || t!=50)$fatal(1,"E7 default PRE2/T50");write_cfg(0,58);').replace('E5 CONTROL','E7 CONTROL')
    p.write_text(text)
    tests=[('tb_e7_gaussian',{}),('tb_e7_output_ab',{}),('tb_e7_rgb_delay',{}),
        ('tb_e7_controls',{}),('tb_control',{}),('tb_e3_controls',{}),
        ('tb_final_hud',dict(PALETTE_PROBE=1,DVI_TRANSPORT=1,QUALITY_FILTER=1)),
        ('tb_m2_starvation',{}),('tb_video_out',{})]
    results=[]
    for top,params in tests:
        sim.run(top,params)
        assert 'PASS' in (BUILD/(top+'_run.log')).read_text()
        results.append(dict(test=top,params=params,status='PASS'))
    (ROOT/'reports/e7_verification.json').write_text(json.dumps(dict(status='PASS',tests=results),indent=2))
    print('E7 FUNCTIONAL VERIFICATION PASS:',len(tests),'groups')

if __name__=='__main__':main()
