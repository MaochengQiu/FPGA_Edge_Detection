"""Publish diagnostic artifacts only after real checks and both real builds."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,subprocess,sys,xml.etree.ElementTree as ET,zipfile
from finalize_e3 import timing

ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'reports'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
shape=lambda e:(e.tag,sorted(e.attrib.items()),[shape(c) for c in e])

def main():
    subprocess.run([sys.executable,str(ROOT/'scripts/check_e4_scope.py')],check=True)
    verification=json.loads((REPORTS/'e4_verification.json').read_text())
    assert verification['status']=='PASS' and len(verification['tests'])==8
    assert 'E4 VERIFICATION PASS' in (REPORTS/'e4_verification.log').read_text(encoding='utf8')
    project_check=json.loads((REPORTS/'project_checks.json').read_text())
    assert project_check['public_interface_elaboration']=='PASS' and project_check['source_files']==78
    assert 'Project metadata regression PASS: 8 cases' in (REPORTS/'e4_structure.log').read_text(encoding='utf8')
    project=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
    sources=[e.get('name') for e in project.iter() if e.tag.endswith('design_file')]
    builds={}
    for variant,folder,stem in [('D',ROOT,'Diagnostic'),('T',ROOT/'work/hdmi_test_release','HDMI_Test')]:
        log=(REPORTS/f'efinity_e4{variant.lower()}_compile.log').read_text(encoding='utf8')
        for stage in ('map','interface','pnr','pgm'):
            assert re.search(r'\b'+stage+r'\s*:\s*PASS',log),(variant,stage)
        assert shape(project)==shape(ET.parse(folder/'ti60f225_oob.xml').getroot())
        for name in sources:
            expected=(ROOT/name).read_bytes()
            if variant=='T' and name=='rtl/ti60f225_oob_top.v':
                expected=expected.replace(b"E4_HDMI_TEST = 1'b0",b"E4_HDMI_TEST = 1'b1")
            assert expected==(folder/name).read_bytes(),('Build source mismatch',variant,name)
        out=folder/'outflow';result=timing(out/'ti60f225_oob.timing.rpt')
        assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
        resources={}
        place=(out/'ti60f225_oob.place.rpt').read_text()
        for label in ('XLRs','Memory Blocks','DSP Blocks'):
            match=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert match
            resources[label]=dict(used=int(match[1]),available=int(match[2]),percent=match[3])
        for suffix in ('timing.rpt','cdc.rpt','place.rpt','map.rpt','log','warn.log','err.log'):
            shutil.copy2(out/('ti60f225_oob.'+suffix),REPORTS/f'e4{variant.lower()}_{suffix}')
        artifacts=[]
        for extension in ('bit','hex'):
            source=out/f'ti60f225_oob.{extension}';assert source.stat().st_size>0
            dest=ROOT/f'programming/ti60f225_oob_V10_E4_{stem}.{extension}'
            assert not dest.exists() or sha(dest)==sha(source),'Refuse firmware overwrite'
            shutil.copy2(source,dest)
            artifacts.append(dict(path=dest.relative_to(ROOT).as_posix(),sha256=sha(dest),size=dest.stat().st_size))
        builds[variant]=dict(status='PASS',timing=result,resources=resources,cdc='No Synchronizer warnings',
            source_sha256={n:sha(folder/n) for n in sources},artifacts=artifacts)
    archive=ROOT/'reference/previous_firmware';archive.mkdir(exist_ok=True)
    for p in (ROOT/'programming').iterdir():
        if p.is_file() and '_E4_' not in p.name:
            dest=archive/p.name
            assert p.resolve().is_relative_to(ROOT) and dest.resolve().is_relative_to(ROOT)
            assert not dest.exists() or sha(dest)==sha(p)
            if not dest.exists():shutil.move(str(p),str(dest))
    lines=['# E4 诊断验证记录','',
        '状态：诊断候选已生成，实板黑屏/无信号根因尚未确认，没有宣称修复。','',
        '用户证据：T/PRE 保持，提示文字也消失或显示器无信号；已换 HDMI 线及摄像头排线；移动整板似乎影响现象，但未建立因果。LED2～7 为历史锁存，不足以证明当前 HDMI 或帧流正常。','',
        '本轮 8 组定向 RTL 检查 PASS，结构/公开接口检查 PASS，元数据 8 个案例 PASS。没有修改边缘核心，不将继承的 E3 图像回归或历史报告当成 E4 新结果。','',
        '| 版本 | 最小setup ns | HDMI setup ns | 最小hold ns | XLR | RAM | DSP |','|---|---:|---:|---:|---:|---:|---:|']
    for v,b in builds.items():
        t=b['timing'];r=b['resources']
        lines.append(f'| E4{v} | +{t["min_setup_ns"]:.3f} | +{t["hdmi_setup_ns"]:.3f} | +{t["min_hold_ns"]:.3f} | {r["XLRs"]["used"]}/60800 | {r["Memory Blocks"]["used"]}/256 | {r["DSP Blocks"]["used"]}/160 |')
    lines += ['', '两版 Efinity 2026.1.132 的 map/interface/pnr/pgm 均 PASS，已报告路径 setup/hold 非负，CDC 无 synchronizer 警告。SDC 与原外设 XML 字节相同，视频时钟双向关系仍检查。既有未使用接口提示保留，不代表全部外部 IO 或电气链路已签核。','',
        '## 有限的诊断结论','',
        '故障注入通过真实 video_out、control 和 E2L 核心：一次欠载造成一帧 M2 黑图，T68/PRE1 保持，同步未中断，随后恢复。这是内容黑屏的确定性复现，不是用户实板 HDMI 无信号的复现。','',
        'M2→M3 在模式键短按后是正常切页；当前没有发现 M2 专门改变 PLL、串化 OE 或全局复位的逻辑。不能因缺少仿真错误就排除时序、电气、连接、供电瞬态或加密编码器相关问题。','',
        'E4T 用独立固定光栅检验共用的编码器/串化输出/时钟/引脚链路；E4D 用同样的正常算法并将 U/D/R/L/O/F、K/LAST、V 暴露到普通页。T 分支独立于相机出帧、DDR 校准和算法输出；D 分支仍选择原复位和原 preencoder 数据。','',
        'T 版稳定不能完全排除负载相关供电或信号问题，因为两版使用资源和开关活动不同；T 版也掉信号则优先查共同输出链路及硬件。最终根因需要实板诊断结果。','',
        '## 下一步','',
        '先固定板子烧 E4T，不调阈值，观察网格/彩条/棋盘与 V 是否持续。再用 E4D 的 M2、T68/PRE1 作为非默认状态标记，记录故障前后 HUD/无信号提示、U/D/R/L/O、K/LAST 和 V。具体流程见 docs/V10_E4_DIAGNOSTICS.md。']
    (REPORTS/'V10_E4_VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    files=[]
    for name in ('rtl','ip','ooc','scripts','sim','reference','docs','programming','reports'):
        for p in (ROOT/name).rglob('*'):
            if p.is_file() and not any(part.startswith('build') or part=='__pycache__' for part in p.relative_to(ROOT).parts):
                if p.name not in ('e4_release_manifest.json','e4_package_verification.json'):files.append(p)
    files += [p for p in ROOT.iterdir() if p.is_file()]
    manifest=dict(revision='V10-E4',status='DIAGNOSTIC_ONLY_NOT_A_CONFIRMED_FIX',
        collected_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        verification=verification,builds=builds,scope=json.loads((REPORTS/'e4_scope.json').read_text()),
        sha256={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(files))})
    path=REPORTS/'e4_release_manifest.json';path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    dest=ROOT.parent/'packages';dest.mkdir(exist_ok=True)
    package=dest/'ti60f225_oob_V10_E4_diagnostics.zip';assert not package.exists(),'Preserve published package'
    with zipfile.ZipFile(package,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name in sorted(manifest['sha256']):z.write(ROOT/name,'ti60f225_oob/'+name)
        z.write(path,'ti60f225_oob/reports/e4_release_manifest.json')
    with zipfile.ZipFile(package) as z:
        assert z.testzip() is None
        for name,h in manifest['sha256'].items():assert hashlib.sha256(z.read('ti60f225_oob/'+name)).hexdigest()==h
        count=len(z.namelist())
    digest=sha(package);package.with_suffix('.sha256').write_text(digest+'  '+package.name+'\n')
    record=dict(status='PASS',path=str(package),sha256=digest,members=count,bytes=package.stat().st_size,
                CRC='PASS',member_sha256='PASS',board_fault='NOT YET ISOLATED')
    (REPORTS/'e4_package_verification.json').write_text(json.dumps(record,indent=2))
    print(json.dumps(record,indent=2))

if __name__=='__main__':main()
