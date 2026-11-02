#!/usr/bin/env python3
"""Snapshot the modified existing V10 project as the C1 delivery; no new project.
C1 reports, original V10 rollback firmware and its baseline archive are included.
"""
from pathlib import Path
import hashlib,json,sys,zipfile

ROOT=Path(__file__).resolve().parents[1]
release=json.loads((ROOT/'reports/v10_c1_release_manifest.json').read_text(encoding='utf-8'))
for name,digest in release['sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,f'Changed after C1 validation: {name}'
dest=ROOT.parents[1]/'packages';dest.mkdir(exist_ok=True)
target=dest/'ti60f225_oob_V10_C1_color.zip'
output=target
if target.exists():
    assert sys.argv[1:]==['--replace'],'C1 package exists; use --replace only for a verified rebuild'
    expected=(dest/'ti60f225_oob_V10_C1_color.sha256').read_text(encoding='ascii').split()[0]
    assert hashlib.sha256(target.read_bytes()).hexdigest()==expected,'Existing package changed; preserve it'
    output=dest/'ti60f225_oob_V10_C1_color.rebuild.zip'
dirs={'rtl','ip','ooc','reference','docs','scripts','sim','programming','reports'}
reports={'V10_C1_VALIDATION.md','verification_c1.json','project_checks.json','project_structure_regression.json',
         'v10_c1_release_manifest.json','c1_scope.json','c1_color_changes.patch',
         'c1_debayer_before.log','c1_debayer_after.log','c1_debayer_spatial.log','rtl_regression_v10_c1.log','efinity_v10_c1_compile.log',
         'c1_timing.rpt','c1_cdc.rpt','c1_resources.rpt','c1_synthesis.log','c1_place_route.log','c1_bitstream.log'}
count=0
with zipfile.ZipFile(output,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for f in sorted(ROOT.rglob('*')):
        if not f.is_file():continue
        p=f.relative_to(ROOT)
        if '__pycache__' in p.parts or f.name=='.lock':continue
        if len(p.parts)>1:
            if p.parts[0] not in dirs:continue
            if p.parts[:2] in (('sim','build'),('reference','v9_programming')):continue
            if p.parts[0]=='reports' and (len(p.parts)!=2 or f.name not in reports):continue
            if p.parts[0]=='programming' and f.name not in ('ti60f225_oob_V10_C1.bit','ti60f225_oob_V10_C1.hex','ti60f225_oob_V10.bit','ti60f225_oob_V10.hex'):continue
        z.write(f,Path('ti60f225_oob')/p);count+=1
with zipfile.ZipFile(output) as z:assert z.testzip() is None
digest=hashlib.sha256(output.read_bytes()).hexdigest()
if output!=target:output.replace(target)
(dest/'ti60f225_oob_V10_C1_color.sha256').write_text(f'{digest}  {target.name}\n',encoding='ascii')
print(f'C1 PACKAGE PASS: {count} files, {target.stat().st_size} bytes');print(target);print(digest)
