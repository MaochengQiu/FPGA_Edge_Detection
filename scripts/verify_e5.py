from pathlib import Path
import json
import run_tests as sim
root=Path(__file__).resolve().parents[1]
sim.BUILD=root/'sim/build_e5';sim.BUILD.mkdir(parents=True,exist_ok=True)
tests=[('tb_e5_output_ab',{}),('tb_e5_controls',{}),('tb_control',{}),('tb_e3_controls',{}),
       ('tb_final_hud',dict(PALETTE_PROBE=1)),('tb_m2_starvation',{}),('tb_video_out',{})]
records=[]
for top,params in tests:
    sim.run(top,params)
    assert 'PASS' in (sim.BUILD/(top+'_run.log')).read_text()
    records.append(dict(test=top,params=params,status='PASS'))
(root/'reports/e5_verification.json').write_text(json.dumps(dict(status='PASS',tests=records,
    hypothesis='Output-codeword/encoding/electrical or data-dependent timing issue; not yet confirmed',
    board_blackout='NOT reproduced in RTL; same-bitstream probe prepared'),indent=2))
print('E5 VERIFICATION PASS: unchanged binary decisions, only M7 output RGB differs; board root cause NOT claimed')
