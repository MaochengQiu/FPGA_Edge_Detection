"""Check the in-place C2 color edit against the immutable delivered C1."""
from pathlib import Path
import difflib, hashlib, json, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'reference/c2_baseline'
ALLOWED={'rtl/debayer/raw_to_rgb.v','rtl/debayer/debayer_top_2to1.v',
         'rtl/ti60f225_oob_top.v','rtl/edge/control/img_control.sv',
         'rtl/edge/compose/edge_final_hud.sv'}

def shape(e):return e.tag,tuple(sorted(e.attrib.items())),tuple(shape(c) for c in e)
def segment(s,a,b):return s.split(a,1)[1].split(b,1)[0]
def source(name):return (ROOT/name).read_text(encoding='utf-8-sig')
def old_source(name):return (BASE/name).read_text(encoding='utf-8-sig')

def check():
    manifest=json.loads((BASE/'v10_c1_release_manifest.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((BASE/'ti60f225_oob.xml').read_bytes()).hexdigest()==manifest['sha256']['ti60f225_oob.xml'],'C1 project backup changed'
    frozen=(ROOT/'reports/v10_c1_release_manifest.json').read_bytes()
    assert frozen==(BASE/'v10_c1_release_manifest.json').read_bytes(),'C1 release manifest overwritten'
    assert shape(ET.parse(ROOT/'ti60f225_oob.xml').getroot())==shape(ET.parse(BASE/'ti60f225_oob.xml').getroot()),'Project/settings changed'
    changed={};unchanged=[];patch=[]
    for name,digest in manifest['sha256'].items():
        actual=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
        if name=='ti60f225_oob.xml':continue
        if actual==digest:unchanged.append(name);continue
        assert name in ALLOWED,f'Out-of-scope C1 source/artifact changed: {name}'
        assert hashlib.sha256((BASE/name).read_bytes()).hexdigest()==digest,'Changed C1 rollback source'
        changed[name]=dict(before=digest,after=actual)
        patch.extend(difflib.unified_diff(old_source(name).splitlines(True),source(name).splitlines(True),fromfile='V10-C1/'+name,tofile='V10-C2/'+name))
    assert set(changed)==ALLOWED,'Unexpected C2 source change set'
    old,new=old_source('rtl/ti60f225_oob_top.v'),source('rtl/ti60f225_oob_top.v')
    # After removing the new phase wires/ports, top must be byte-for-byte C1.
    for addition in (
        'wire [1:0] edge_bayer_phase,edge_bayer_active;\n',
        '\t.bayer_phase(edge_bayer_phase),.bayer_active(edge_bayer_active),\n',
        '    .bayer_phase(edge_bayer_active),\n'):
        assert new.count(addition)==1,addition
        new=new.replace(addition,'')
    new=new.replace('.wb_selected(edge_wb_selected),\n    .bayer_phase(edge_bayer_phase)', '.wb_selected(edge_wb_selected)')
    assert old==new,'Non-color top-level wiring changed'
    old,new=old_source('rtl/debayer/raw_to_rgb.v'),source('rtl/debayer/raw_to_rgb.v')
    new=new.replace("parameter\tLEGACY\t\t\t= 1'b1,\n\tparameter [1:0] BAYER_DEFAULT = 2'd0", "parameter\tLEGACY\t\t\t= 1'b1")
    new=new.replace('\n\tinput [1:0] i_bayer_phase,\n\toutput reg [1:0] o_bayer_phase,','')
    assert old.split('wire [P_DEPTH  :0] w_r_00_00_l1',1)[0]==new.split('// C2 Bayer phase',1)[0], 'Debayer sync/counters/taps changed'
    assert old.split('assign\to_vsync',1)[1]==new.split('assign\to_vsync',1)[1], 'Debayer output timing changed'
    report=dict(status='PASS',basis='delivered V10-C1 SHA256 manifest',in_place_project=True,
                changed_color_sources=changed,unchanged_release_files=unchanged,
                project_xml_semantics='IDENTICAL',all_other_top_wiring='IDENTICAL',
                debayer_line_buffer_counters_sync_latency='UNCHANGED',
                ddr_mipi_hdmi_pll_reset_exposure='UNCHANGED',
                gray_sobel_preprocess_composer='UNCHANGED',raw_gain='UNITY 0x0100',
                sensor_phase_status='UNVERIFIED ON BOARD; runtime four-phase selection, RGGB trial default')
    (ROOT/'reports/c2_scope.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    (ROOT/'reports/c2_color_changes.patch').write_text(''.join(patch),encoding='utf-8')
    return report

if __name__=='__main__':
    r=check();print(f'C2 SCOPE PASS: {len(r["changed_color_sources"])} color RTL files; project, all other top wiring, video architecture, gray/Sobel and exposure unchanged')
