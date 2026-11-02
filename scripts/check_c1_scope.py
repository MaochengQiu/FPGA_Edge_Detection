#!/usr/bin/env python3
"""Verify that the in-place C1 edit stays within the V10 color scope.
Compare against the immutable delivered V10 manifest and rollback archive.
"""
from pathlib import Path
import difflib,hashlib,json,zipfile,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'reference/c1_baseline'
ALLOWED={
    'rtl/debayer/raw_to_rgb.v','rtl/ti60f225_oob_top.v',
    'rtl/edge/compose/edge_color_balance.sv','rtl/edge/control/img_control.sv',
    'rtl/edge/compose/edge_rgb_statistics.sv','rtl/edge/compose/edge_final_hud.sv'}
def shape(e):return (e.tag,tuple(sorted(e.attrib.items())),tuple(shape(c) for c in e))
def between(text,start,end):return text.split(start,1)[1].split(end,1)[0]
def check():
    baseline=json.loads((BASE/'v10_release_manifest.json').read_text(encoding='utf-8'))
    archive=BASE/'V10_source_before_C1.zip'
    assert hashlib.sha256(archive.read_bytes()).hexdigest()=='d361de112319fddbbdb8450fccbcb8d157077b2de03b1d41f01f1dcc4191f715','Rollback archive changed'
    changed={};unchanged=[];patch=[]
    with zipfile.ZipFile(archive) as z:
        old_xml=z.read('ti60f225_oob/ti60f225_oob.xml')
        assert shape(ET.fromstring(old_xml))==shape(ET.parse(ROOT/'ti60f225_oob.xml').getroot()),'Project/settings changed'
        for name,expected in baseline['sha256'].items():
            actual=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
            if name=='ti60f225_oob.xml':continue # serialized whitespace is not hardware
            if actual==expected:unchanged.append(name);continue
            assert name in ALLOWED,f'Out-of-scope source/artifact changed: {name}'
            changed[name]=dict(before=expected,after=actual)
            old=z.read('ti60f225_oob/'+name).decode('utf-8-sig').replace('\r\n','\n')
            new=(ROOT/name).read_text(encoding='utf-8-sig')
            patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),
                         fromfile='V10/'+name,tofile='V10-C1/'+name))
        name='rtl/ti60f225_oob_top.v'
        old=z.read('ti60f225_oob/'+name).decode('utf-8-sig').replace('\r\n','\n')
        new=(ROOT/name).read_text(encoding='utf-8-sig')
        # The top-level file also owns video/reset wiring. Check its protected
        # blocks directly, rather than treating all top-level edits as color.
        assert old.split('wire        rgb_vs;',1)[0]==new.split('wire        rgb_vs;',1)[0],'Capture/DDR/raster/reset prefix changed'
        for start,end in (
            ('reg rgb_vs_r','// V3: diagnostic event toggles'),
            ('// V3: diagnostic event toggles','// Pixel-domain color balance'),
            ('img_pipeline #(','// V3: diagnostic HUD'),
            ('// V3: diagnostic HUD','// V8: final-encoder HUD')):
            assert between(old,start,end)==between(new,start,end),f'Protected top block changed: {start}'
        assert old.split('dvi_encoder dvi_encoder_m0',1)[1]==new.split('dvi_encoder dvi_encoder_m0',1)[1],'HDMI/debug/diagnostic suffix changed'
        assert "localparam C1_LEGACY_RAW_VIO_GAIN=1'b0;" in new,'RAW gain must be unity for C1'
    assert set(changed)==ALLOWED,'Unexpected/incomplete C1 source change set'
    report=dict(status='PASS',basis='V10 delivered SHA256 manifest',in_place_project=True,
                changed_color_sources=changed,unchanged_release_files=unchanged,
                project_xml_semantics='IDENTICAL',top_protected_video_blocks='IDENTICAL',
                ddr_mipi_hdmi_pll_reset_exposure='UNCHANGED',sobel_gray_preprocess_composer='UNCHANGED',
                rollback_archive=str(archive),rollback_archive_sha256='d361de112319fddbbdb8450fccbcb8d157077b2de03b1d41f01f1dcc4191f715')
    (ROOT/'reports/c1_scope.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    (ROOT/'reports/c1_color_changes.patch').write_text(''.join(patch),encoding='utf-8')
    return report
if __name__=='__main__':
    result=check()
    print(f"C1 SCOPE PASS: {len(result['changed_color_sources'])} color source files; original project/video architecture/settings, gray/Sobel and exposure unchanged")
