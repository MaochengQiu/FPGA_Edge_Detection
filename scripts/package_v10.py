#!/usr/bin/env python3
"""Package V10 sources, programming files and final reports; omit caches.
Uses exclusive creation: never overwrite an existing delivery zip.
"""
from pathlib import Path
import hashlib,json,zipfile

ROOT=Path(__file__).resolve().parents[1]
release=json.loads((ROOT/'reports/v10_release_manifest.json').read_text(encoding='utf-8'))
for name,expected in release['sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected, f'Changed after validation: {name}'
DEST=ROOT.parents[1]/'packages';DEST.mkdir(exist_ok=True)
target=DEST/'ti60f225_oob_V10_threshold.zip'
dirs={'rtl','ip','ooc','reference','docs','scripts','sim','programming','reports'}
reports={'V10_VALIDATION.md','verification.json','project_checks.json','project_structure_regression.json',
         'v10_release_manifest.json','v10_timing.rpt','v10_cdc.rpt','v10_resources.rpt',
         'rtl_regression_v10.log','v10_synthesis.log','v10_place_route.log','v10_bitstream.log'}
count=0
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for f in sorted(ROOT.rglob('*')):
        if not f.is_file():continue
        p=f.relative_to(ROOT)
        if '__pycache__' in p.parts or f.name=='.lock':continue
        if len(p.parts)>1:
            if p.parts[0] not in dirs:continue
            if p.parts[:2]==('sim','build'):continue
            if p.parts[:2]==('reference','v9_programming'):continue
            if p.parts[0]=='reports' and (len(p.parts)!=2 or f.name not in reports):continue
        z.write(f,Path('ti60f225_oob')/p);count+=1
with zipfile.ZipFile(target) as z:assert z.testzip() is None
digest=hashlib.sha256(target.read_bytes()).hexdigest()
(DEST/'ti60f225_oob_V10_threshold.sha256').write_text(f'{digest}  {target.name}\n',encoding='ascii')
print(f'PACKAGE PASS: {count} files, {target.stat().st_size} bytes')
print(target);print(digest)
