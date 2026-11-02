"""Collect real tests/builds; reject failed checks or different published firmware."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
from check_e3_scope import main as scope

ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'reports'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def shape(e):return e.tag,sorted(e.attrib.items()),[shape(c) for c in e]

def timing(path):
    text=path.read_text()
    summary=text.split('Setup (Max) Clock Relationship',1)[1].split('NOTE: Values',1)[0]
    setup,hold=summary.split('Hold (Min) Clock Relationship',1)
    def rows(section):
        return [dict(launch=m[0],capture=m[1],constraint=float(m[2]),slack=float(m[3])) for m in
                re.findall(r'^\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(R-R\)',section,re.M)]
    a,b=rows(setup),rows(hold)
    assert a and b and min(r['slack'] for r in a+b)>=0,'Timing did not pass'
    for launch,capture in (('vid_clk_dvi2','hdmi_tx_slow_clk'),('hdmi_tx_slow_clk','vid_clk_dvi2')):
        assert any(r['launch']==launch and r['capture']==capture for r in a),'Video clock relationship omitted'
    return dict(min_setup_ns=min(r['slack'] for r in a),min_hold_ns=min(r['slack'] for r in b),
                hdmi_setup_ns=next(r['slack'] for r in a if r['launch']==r['capture']=='hdmi_tx_slow_clk'))

def main():
    scope()
    assert 'ALL REGRESSIONS PASSED' in (REPORTS/'e3_regression.log').read_text(encoding='utf8')
    regression=json.loads((REPORTS/'verification.json').read_text())
    assert regression and all(t['status']=='PASS' for t in regression)
    validations={}
    for name in ('e3_local_verification','e3_image_verification','e3_controls_verification','e3_scope'):
        validations[name]=json.loads((REPORTS/(name+'.json')).read_text())
        assert validations[name]['status']=='PASS'
    structure=json.loads((REPORTS/'project_checks.json').read_text())
    assert structure['public_interface_elaboration']=='PASS'
    assert 'Project metadata regression PASS' in (REPORTS/'e3_structure.log').read_text(encoding='utf8')
    project=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
    sources=[e.get('name') for e in project.iter() if e.tag.endswith('design_file')]
    builds={}
    for variant,folder,stem in [('W',ROOT,'Weak'),('B',ROOT/'work/baseline_release','Baseline')]:
        text=(REPORTS/f'efinity_e3{variant.lower()}_compile.log').read_text(encoding='utf8')
        assert all(re.search(r'\b'+stage+r'\s*:\s*PASS',text) for stage in ('map','interface','pnr','pgm'))
        assert shape(ET.parse(folder/'ti60f225_oob.xml').getroot())==shape(project)
        for name in sources:
            a=(ROOT/name).read_bytes();b=(folder/name).read_bytes()
            if variant=='B' and name=='rtl/ti60f225_oob_top.v':
                assert b==a.replace(b"E3_WEAK_CHAIN_ENABLE = 1'b1",b"E3_WEAK_CHAIN_ENABLE = 1'b0")
            else:assert a==b,('Different build source',variant,name)
        out=folder/'outflow'
        assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
        t=timing(out/'ti60f225_oob.timing.rpt');place=(out/'ti60f225_oob.place.rpt').read_text()
        resources={}
        for label in ('XLRs','Memory Blocks','DSP Blocks'):
            m=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
            resources[label]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
        for suffix in ('timing.rpt','cdc.rpt','place.rpt','map.rpt','log','warn.log','err.log'):
            shutil.copy2(out/('ti60f225_oob.'+suffix),REPORTS/f'e3{variant.lower()}_{suffix}')
        artifacts=[]
        for extension in ('bit','hex'):
            source=out/f'ti60f225_oob.{extension}';assert source.stat().st_size>0
            target=ROOT/f'programming/ti60f225_oob_V10_E3_{stem}.{extension}'
            assert not target.exists() or sha(target)==sha(source),'Refuse different firmware overwrite'
            shutil.copy2(source,target)
            artifacts.append(dict(path=target.relative_to(ROOT).as_posix(),sha256=sha(target),size=target.stat().st_size))
        builds[variant]=dict(status='PASS',timing=t,resources=resources,cdc='No Synchronizer warnings',
                             source_sha256={n:sha(folder/n) for n in sources},artifacts=artifacts)
    assert builds['W']['artifacts'][0]['sha256']!=builds['B']['artifacts'][0]['sha256'],'Two firmware images unexpectedly identical'
    archive=ROOT/'reference/e2_firmware';archive.mkdir(exist_ok=True)
    for path in (ROOT/'programming').glob('*_E2_*'):
        target=archive/path.name
        assert not target.exists() or sha(target)==sha(path)
        if not target.exists():shutil.move(str(path),str(target))
    image=validations['e3_image_verification']
    lines=['# V10-E3 实际验证记录','',
        '这是候选实验版的离线结果。没有 E3 实板反馈，不能宣布真实画质、随机跳点或长期 HDMI 稳定性已改善。','',
        f'完整回归 {len(regression)} 组 PASS；局部图 {len(validations["e3_local_verification"]["cases"])} 配置 PASS；固定输入实际 RTL 输出 {image["rtl_outputs"]} 个，逐像素与独立模型、逐时钟同步一致。',
        '额外验证 PRE0..3 长按循环、帧边界提交、颜色保持、E3B/E3W 字符显示；编译器仍拒绝缺失模块。','',
        '| 固件 | 最小setup ns | 最小hold ns | XLR | RAM块 | DSP |','|---|---:|---:|---:|---:|---:|']
    for v,b in builds.items():
        t=b['timing'];r=b['resources']
        lines.append(f'| E3{v} | +{t["min_setup_ns"]:.3f} | +{t["min_hold_ns"]:.3f} | {r["XLRs"]["used"]}/60800 | {r["Memory Blocks"]["used"]}/256 | {r["DSP Blocks"]["used"]}/160 |')
    lines += ['', 'SDC 保持，74.25/148.5 MHz 视频时钟双向关系仍被检查；CDC 无 synchronizer 警告。既有未使用接口引脚提示仍存在，已报告路径通过不等于全部外部 IO 签核。', '',
        '## 固定输入的变化','',
        'B 是原 E2L 算法，W 是补充路径。两者输入、预处理旁路和阈值相同；W 为 B 与补充路径的并集，本来就不会减少 B 已输出的噪点。白点变化不是真实召回率。','',
        '| 输入 | H50新增像素 | H68新增像素 |','|---|---:|---:|']
    for row in image['fixtures']:lines.append(f'| {row["name"]} | {row["added_H50"]} | {row["added_H68"]} |')
    lines += ['', '## 已知平坦背景 ROI 的误响应','',
              '| 合成噪声 | B50 | W50 | B68 | W68 |','|---|---:|---:|---:|---:|']
    for row in image['fixtures']:
        if row['name'].startswith('flat_noise'):
            values=[row[v]['known_flat_roi_false_pixels'] for v in ('B50','W50','B68','W68')]
            lines.append('| '+row['name']+' | '+' | '.join(map(str,values))+' |')
    lines += ['', '现有固定图收益较小，部分合成噪声多出少量响应。不要将本版称为普遍更准确或更干净。新增规则可以恢复定向描述符用例中的一强种子直弱段；杯纹、低对比区域和长弱轮廓仍需实板判断。', '',
              '## 改动与工具','', '硬件只改 img_edge_link、img_pipeline、edge_final_hud 和顶层四个 RTL 文件；颜色、相机、视频链路、约束保持，项目 XML 仅被 Efinity 等价序列化。原 E2 发布文件按清单及已知迁移 XML 例外核验。', '',
              '实际 RTL 使用 Icarus v12 的 ivlpp/ivl/vvp；Windows driver 崩溃通过直接调用这三个原版阶段解决，所有退出码仍检查。两版实际 Efinity 2026.1.132 compile 全阶段通过。接口工具从工作区副本运行，未修改供应商源码。']
    (REPORTS/'V10_E3_VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    delivered=[]
    for name in ('rtl','ip','ooc','scripts','sim','reference','docs','programming','reports'):
        for p in (ROOT/name).rglob('*'):
            if p.is_file() and not any(part.startswith('build') or part=='__pycache__' for part in p.relative_to(ROOT).parts):
                if p.name!='e3_release_manifest.json':delivered.append(p)
    delivered += [p for p in ROOT.iterdir() if p.is_file()]
    manifest=dict(revision='V10-E3',collected_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        status='EXPERIMENT_READY_FOR_BOARD_AB',regressions=len(regression),validations=validations,builds=builds,
        hardware='NOT TESTED',sha256={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(delivered))})
    (REPORTS/'e3_release_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    print('E3 collected: fresh tests, two real builds, timing/CDC, firmware SHA256; board quality NOT claimed')

if __name__=='__main__':main()
