from pathlib import Path
import json
import run_tests as sim

root=Path(__file__).resolve().parents[1]
sim.BUILD=root/'sim/build_e4';sim.BUILD.mkdir(parents=True,exist_ok=True)
records=[]
for top,params in [
    ('tb_m2_starvation',{}),('tb_control',{}),('tb_e3_controls',{}),('tb_video_out',{}),
    ('tb_final_hud',{'TEST_PATTERN':0}),('tb_final_hud',{'TEST_PATTERN':1}),
    ('tb_hdmi_test_pattern',{}),
    ('tb_hdmi_test_pattern',dict(W=1920,H=1080,HFP=88,HSP=44,HBP=148,VFP=4,VSP=5,VBP=36,FRAME_COUNT=2))]:
    sim.run(top,params)
    log=(sim.BUILD/(top+'_run.log')).read_text()
    assert 'PASS' in log,(top,params,'No pass marker')
    records.append(dict(test=top,params=params,status='PASS'))
(root/'reports/e4_verification.json').write_text(json.dumps(dict(status='PASS',tests=records,
    physical_HDMI_fault='NOT REPRODUCED remotely; diagnostic firmware prepared to isolate it',
    injection='Data starvation produces black content with retained UI and continuous sync'),indent=2))
print('E4 VERIFICATION PASS: 8 checks; fault injection is not a claim of reproducing physical HDMI loss')
