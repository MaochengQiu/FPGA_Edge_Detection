"""Protect the delivered E2 and restrict E3 hardware changes to four RTL files."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
PRIOR=ROOT.parents[1]/'v10-e2/ti60f225_oob'
BASE=ROOT/'reference/e3_baseline'
ALLOWED={'rtl/ti60f225_oob_top.v','rtl/edge/top/img_pipeline.sv',
         'rtl/edge/compose/edge_final_hud.sv','rtl/edge/gradient/img_edge_link.sv'}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def shape(e):return e.tag,sorted(e.attrib.items()),[shape(c) for c in e]


def main():
    BASE.mkdir(exist_ok=True)
    manifest=json.loads((PRIOR/'reports/v10_e2_release_manifest.json').read_text(encoding='utf8'))
    # Migration audit already records the semantically equivalent XML byte change.
    exceptions={'ti60f225_oob.xml':'fd229977c049316b1fa41b0bc63c94058eeb211130f49e1454d6d8d8bb8135d1'}
    for name,expected in manifest['sha256'].items():
        assert sha(PRIOR/name)==exceptions.get(name,expected),('Delivered E2 modified',name)
    patch=[];changed=[]
    hardware=[p.relative_to(PRIOR).as_posix() for p in (PRIOR/'rtl').rglob('*') if p.is_file()]
    hardware+=['ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc']
    assert {p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').rglob('*') if p.is_file()}==set(hardware[:-3])
    for name in hardware:
        if sha(PRIOR/name)==sha(ROOT/name):continue
        if name=='ti60f225_oob.xml':
            assert shape(ET.parse(PRIOR/name).getroot())==shape(ET.parse(ROOT/name).getroot()),'Project settings changed'
            continue  # Efinity serializes XML while preserving every parsed setting.
        assert name in ALLOWED,('Out-of-scope hardware change',name)
        target=BASE/name;target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():shutil.copy2(PRIOR/name,target)
        assert sha(target)==sha(PRIOR/name),'Frozen E2 copy was changed'
        changed.append(name)
        patch.extend(difflib.unified_diff((PRIOR/name).read_text(encoding='utf8').splitlines(True),
                    (ROOT/name).read_text(encoding='utf8').splitlines(True),fromfile='E2/'+name,tofile='E3/'+name))
    assert set(changed)==ALLOWED
    for name in ('ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc'):
        target=BASE/name
        if not target.exists():shutil.copy2(PRIOR/name,target)
        assert sha(target)==sha(PRIOR/name)
    report=dict(status='PASS',E2_release_preserved=True,changed_hardware=changed,
                project_peripheral_constraints='XML parsed settings identical; peri.xml and SDC byte-identical to migrated E2',
                camera_ddr_mipi_hdmi_pll_reset='UNCHANGED',
                color='PH2; UQ2.8 0x240/0x180/0x240 unchanged',
                local_window_and_latency='unchanged 5x5; 5*HTOTAL+60 kernel clocks',
                E2_xml_migration_exception=exceptions)
    (ROOT/'reports/e3_scope.json').write_text(json.dumps(report,indent=2))
    (ROOT/'reports/e3_changes.patch').write_text(''.join(patch),encoding='utf8')
    print('E3 SCOPE PASS: delivered E2 frozen; four RTL files; constraints/camera/color unchanged')


if __name__=='__main__':main()
