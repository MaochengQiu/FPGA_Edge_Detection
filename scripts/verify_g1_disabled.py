from pathlib import Path
import re
import run_tests as s
r=Path(__file__).resolve().parents[1];s.BUILD=r/'sim/build_g1_disabled';s.BUILD.mkdir(parents=True,exist_ok=True)
ps=list((r/'sim/reference/e7_resource').glob('*.sv'));names=[]
for p in ps:names+=re.findall(r'^module\s+(\w+)',p.read_text(),re.M)
pattern=re.compile(r'\b('+'|'.join(names)+r')\b');extra=[]
for p in ps:
 t=s.BUILD/('ref_'+p.name);t.write_text(pattern.sub(lambda m:'e7_ref_'+m[1],p.read_text()));extra.append(str(t))
s.TB_RTL['tb_g1_disabled']=extra
s.run('tb_g1_disabled',dict(FRAMES=8))
assert 'G1 DISABLED PASS' in (s.BUILD/'tb_g1_disabled_run.log').read_text()
print('G1 DISABLED VERIFICATION PASS')
