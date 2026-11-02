"""Preserve the delivered C1 color sources before the in-place C2 update."""
from pathlib import Path
import hashlib, json, shutil, zipfile

ROOT = Path(__file__).resolve().parents[1]
manifest = ROOT / 'reports/v10_c1_release_manifest.json'
release = json.loads(manifest.read_text(encoding='utf-8'))
for name, digest in release['sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, name
package = ROOT.parents[1] / 'packages/ti60f225_oob_V10_C1_color.zip'
assert hashlib.sha256(package.read_bytes()).hexdigest() == 'fc6497733ccb9a3ff9efee04f34bf658a7a6cb7667ebc217ee5bd169fc59a2d3'
base = ROOT / 'reference/c2_baseline'
assert not base.exists(), 'Existing C2 baseline must be preserved'
names = [
    'rtl/debayer/raw_to_rgb.v', 'rtl/debayer/debayer_top_2to1.v',
    'rtl/ti60f225_oob_top.v', 'rtl/edge/control/img_control.sv',
    'rtl/edge/compose/edge_final_hud.sv', 'README.md',
    'sim/tb_control_white_balance.sv', 'sim/tb_final_hud.sv',
    'sim/tb_debayer_color.sv', 'scripts/run_tests.py',
]
with zipfile.ZipFile(package) as archive:
    for name in names:
        data = archive.read('ti60f225_oob/' + name)
        assert data == (ROOT/name).read_bytes(), name
        destination = base / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
shutil.copy2(manifest, base / manifest.name)
print(f'C1 BASELINE PASS: {len(release["sha256"])} released hashes verified; {len(names)} rollback files preserved')
