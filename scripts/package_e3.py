"""Package exactly the verified manifest files, then CRC and hash every member."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]
manifest=ROOT/'reports/e3_release_manifest.json'
data=json.loads(manifest.read_text(encoding='utf8'))
assert data['status']=='EXPERIMENT_READY_FOR_BOARD_AB'
paths=data['sha256']
for name,expected in paths.items():
    path=(ROOT/name).resolve();assert path.is_relative_to(ROOT)
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected,('Release changed',name)
dest=ROOT.parent/'packages';dest.mkdir(exist_ok=True)
archive=dest/'ti60f225_oob_V10_E3_weak_chain_experiment.zip'
assert not archive.exists(),'Preserve published package'
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for name in sorted(paths):z.write(ROOT/name,'ti60f225_oob/'+name)
    z.write(manifest,'ti60f225_oob/reports/e3_release_manifest.json')
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name,expected in paths.items():
        assert hashlib.sha256(z.read('ti60f225_oob/'+name)).hexdigest()==expected
    count=len(z.namelist())
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.sha256').write_text(digest+'  '+archive.name+'\n')
report=dict(status='PASS',path=str(archive),sha256=digest,bytes=archive.stat().st_size,members=count,
            crc='PASS',member_sha256='PASS',hardware='NOT TESTED')
(ROOT/'reports/e3_package_verification.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
