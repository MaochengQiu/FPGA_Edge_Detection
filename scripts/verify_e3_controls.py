from pathlib import Path
import json
import run_tests as sim
from icarus_direct import compile_sources

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'sim/build_e3_controls';BUILD.mkdir(parents=True,exist_ok=True);sim.BUILD=BUILD
sim.run('tb_e3_controls')
for enabled in (0,1):sim.run('tb_final_hud',{'WEAK_CHAIN_ENABLE':enabled})
# The alternative tool invocation must still reject a genuine compiler error.
invalid=BUILD/'invalid_source.v'
invalid.write_text('module broken; deliberately_invalid_instance missing(); endmodule\n')
result=compile_sources([invalid],'broken',BUILD/'invalid.vvp',BUILD)
(BUILD/'invalid_compile.log').write_text(result.stdout+result.stderr)
assert result.returncode!=0,'Missing module was silently accepted'
report=dict(status='PASS',long_press_cycles=8,PRE_modes=[0,1,2,3],color_preserved=True,
            HUD_variants=['E3B','E3W'],compiler_missing_module_rejected=True)
(ROOT/'reports/e3_controls_verification.json').write_text(json.dumps(report,indent=2))
print('E3 CONTROLS PASS: PRE long press/frame commit/visible labels, W/B markers, compiler error rejected')
