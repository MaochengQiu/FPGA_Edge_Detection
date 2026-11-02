"""Package verified C2.1 sources and firmware, preserving prior releases."""
from pathlib import Path
import hashlib, json, zipfile

ROOT=Path(__file__).resolve().parents[1]
release=json.loads((ROOT/'reports/v10_c21_release_manifest.json').read_text(encoding='utf-8'))
for name,digest in release['sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'Changed after validation: '+name
dest=ROOT.parents[1]/'packages';dest.mkdir(exist_ok=True)
target=dest/'ti60f225_oob_V10_C2_1_preset.zip'
assert not target.exists(),'Existing C2.1 package must be preserved'
dirs={'rtl','ip','ooc','reference','docs','scripts','sim','programming','reports'}
reports={'V10_C21_VALIDATION.md','verification_c21.json','v10_c21_release_manifest.json',
    'c21_scope.json','c21_changes.patch','c21_project_checks.log',
    'rtl_regression_v10_c21.log','efinity_v10_c21_compile.log',
    'c21_timing.rpt','c21_cdc.rpt','c21_resources.rpt','c21_synthesis.log','c21_place_route.log','c21_bitstream.log',
    'project_checks.json','project_structure_regression.json','board_interface_compile.log',
    'V10_C2_VALIDATION.md','v10_c2_release_manifest.json','verification_c2.json',
    'V10_C1_VALIDATION.md','v10_c1_release_manifest.json','verification_c1.json','v10_release_manifest.json'}
firmware={f'ti60f225_oob_{version}.{ext}' for version in ('V10','V10_C1','V10_C2','V10_C2_1') for ext in ('bit','hex')}
count=0
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for f in sorted(ROOT.rglob('*')):
        if not f.is_file():continue
        p=f.relative_to(ROOT)
        if '__pycache__' in p.parts or f.name=='.lock':continue
        if len(p.parts)>1:
            if p.parts[0] not in dirs:continue
            if p.parts[:2] in (('sim','build'),('reference','v9_programming')):continue
            if p.parts[0]=='reports' and (len(p.parts)!=2 or f.name not in reports):continue
            if p.parts[0]=='programming' and f.name not in firmware:continue
        z.write(f,Path('ti60f225_oob')/p);count+=1
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    for name,digest in release['sha256'].items():
        assert hashlib.sha256(z.read('ti60f225_oob/'+name)).hexdigest()==digest,name
digest=hashlib.sha256(target.read_bytes()).hexdigest()
(dest/'ti60f225_oob_V10_C2_1_preset.sha256').write_text(f'{digest}  {target.name}\n',encoding='ascii')
print(f'C2.1 PACKAGE PASS: {count} files, {target.stat().st_size} bytes');print(target);print(digest)
