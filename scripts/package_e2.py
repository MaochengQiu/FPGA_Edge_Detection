"""Package verified E2 sources, both firmware images, inputs and evidence."""
from pathlib import Path
import hashlib,json,zipfile

ROOT=Path(__file__).resolve().parents[1]
release=json.loads((ROOT/'reports/v10_e2_release_manifest.json').read_text(encoding='utf-8'))
for name,digest in release['sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
dest=ROOT.parents[1]/'packages';dest.mkdir(exist_ok=True)
target=dest/'ti60f225_oob_V10_E2_link_experiment.zip'
assert not target.exists(),'Preserve the existing E2 package'

dirs={'rtl','ip','ooc','reference','scripts','sim','docs','programming','reports'}
root_files={'README.md','BUILD_NEW_FIRMWARE_REQUIRED.txt','NOTICE.txt','debug_top.v',
    'debug.json','debug_profile.wizard.json','package_settings.xml','Panel_1080p_reg.mem',
    'yuvpattern_mif.memh','ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc'}
reports={Path(n).name for n in release['sha256'] if n.startswith('reports/') and len(Path(n).parts)==2}
reports.add('v10_e2_release_manifest.json')
count=0
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for f in sorted(ROOT.rglob('*')):
        if not f.is_file():continue
        p=f.relative_to(ROOT)
        if '__pycache__' in p.parts or f.name=='.lock':continue
        if len(p.parts)==1:
            if f.name not in root_files:continue
        else:
            if p.parts[0] not in dirs:continue
            if p.parts[:2] in (('sim','build'),('reference','v9_programming')):continue
            if p.parts[0]=='reports' and p.parts[1]!='e2_ab' and (len(p.parts)!=2 or f.name not in reports):continue
        z.write(f,Path('ti60f225_oob')/p);count+=1
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    for name,digest in release['sha256'].items():
        assert hashlib.sha256(z.read('ti60f225_oob/'+name)).hexdigest()==digest,name
    metadata=z.read('ti60f225_oob/ti60f225_oob.xml').decode('utf-8-sig')
    import xml.etree.ElementTree as ET
    for e in ET.fromstring(metadata).iter():
        if e.tag.rsplit('}',1)[-1]=='design_file':assert 'ti60f225_oob/'+e.get('name') in z.namelist()
digest=hashlib.sha256(target.read_bytes()).hexdigest()
(dest/'ti60f225_oob_V10_E2_link_experiment.sha256').write_text(f'{digest}  {target.name}\n',encoding='ascii')
print(f'E2 PACKAGE PASS: {count} files, {target.stat().st_size} bytes')
print(target);print(digest)
