"""Package E1 experiment, A/B firmware, frozen baseline and measured figures."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1]
release=json.loads((ROOT/'reports/v10_e1_release_manifest.json').read_text(encoding='utf-8'))
for name,digest in release['sha256'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
dest=ROOT.parents[1]/'packages';dest.mkdir(exist_ok=True)
target=dest/'ti60f225_oob_V10_E1_NMS_experiment.zip'
assert not target.exists(),'Preserve existing E1 package'
dirs={'rtl','ip','reference','scripts','sim','docs','programming','reports','ooc'}
reports={'V10_E1_VALIDATION.md','v10_e1_release_manifest.json','e1_scope.json','e1_changes.patch',
    'verification_e1.json','e1_algorithm_verification.json','e1_algorithm.log','e1_focused.log',
    'rtl_regression_v10_e1.log','e1_project_checks.log','project_checks.json','project_structure_regression.json',
    'board_interface_compile.log','e1_images_nms0.log','e1_images_nms1.log',
    'efinity_v10_e1_nms_compile.log','efinity_v10_e1_sobel_compile.log',
    'v10_c21_release_manifest.json','v10_c2_release_manifest.json','v10_c1_release_manifest.json','v10_release_manifest.json'}
reports|={f'e1_{v}_{suffix}' for v in ('nms','sobel') for suffix in ('timing.rpt','cdc.rpt','resources.rpt','synthesis.log','place_route.log','bitstream.log')}
count=0
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for f in sorted(ROOT.rglob('*')):
        if not f.is_file():continue
        p=f.relative_to(ROOT)
        if '__pycache__' in p.parts or f.name=='.lock':continue
        if len(p.parts)>1:
            if p.parts[0] not in dirs:continue
            if p.parts[:2] in (('sim','build'),('reference','v9_programming')):continue
            if p.parts[0]=='reports' and p.parts[1]!='e1_ab' and (len(p.parts)!=2 or f.name not in reports):continue
        z.write(f,Path('ti60f225_oob')/p);count+=1
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    for name,digest in release['sha256'].items():assert hashlib.sha256(z.read('ti60f225_oob/'+name)).hexdigest()==digest,name
digest=hashlib.sha256(target.read_bytes()).hexdigest()
(dest/'ti60f225_oob_V10_E1_NMS_experiment.sha256').write_text(f'{digest}  {target.name}\n',encoding='ascii')
print(f'E1 PACKAGE PASS: {count} files, {target.stat().st_size} bytes');print(target);print(digest)
