"""Create an isolated E1 working copy from the verified color-complete C2.1."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[3]
stable=ROOT/'v10/ti60f225_oob'
release=json.loads((stable/'reports/v10_c21_release_manifest.json').read_text(encoding='utf-8'))
for name,digest in release['sha256'].items():
    assert hashlib.sha256((stable/name).read_bytes()).hexdigest()==digest,name
package=ROOT/'packages/ti60f225_oob_V10_C2_1_preset.zip'
assert hashlib.sha256(package.read_bytes()).hexdigest()=='80edb6cb19799c52ef73d8f7eba8ca4a3de8b2cac8d4127efe956ada3589425f'
target=ROOT/'e1';assert not target.exists(),'Preserve existing E1 work'
with zipfile.ZipFile(package) as z:
    assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
    z.extractall(target)
project=target/'ti60f225_oob'
baseline=project/'reference/e1_baseline';baseline.mkdir()
with zipfile.ZipFile(package) as z:
    for name in ('rtl/edge/top/img_pipeline.sv','rtl/edge/compose/edge_final_hud.sv','rtl/ti60f225_oob_top.v','ti60f225_oob.xml'):
        dest=baseline/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(z.read('ti60f225_oob/'+name))
    (baseline/'v10_c21_release_manifest.json').write_bytes(z.read('ti60f225_oob/reports/v10_c21_release_manifest.json'))
work=project/'work';work.mkdir()
(work/'efinity_user.ini').write_text('[General]\nEFINITY_USER_DIR='+work.as_posix()+'/efinity_user\n',encoding='ascii')
print('E1 isolated copy ready:',project)
print('Stable color project and its firmware unchanged:',stable)
