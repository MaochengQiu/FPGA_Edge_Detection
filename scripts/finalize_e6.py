from pathlib import Path
import datetime,hashlib,json,re,shutil,xml.etree.ElementTree as ET,zipfile
from finalize_e3 import timing
from check_e6_scope import main as check_scope

ROOT=Path(__file__).resolve().parents[1];REPORTS=ROOT/'reports'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    scope=check_scope()
    tests=json.loads((REPORTS/'e6_verification.json').read_text())
    assert tests['status']=='PASS' and len(tests['tests'])==8
    assert 'E6 VERIFICATION PASS' in (REPORTS/'e6_verification.log').read_text(encoding='utf8')
    structure=json.loads((REPORTS/'project_checks.json').read_text())
    assert structure['public_interface_elaboration']=='PASS' and structure['source_files']==80
    assert 'Project metadata regression PASS: 8 cases' in (REPORTS/'e6_structure.log').read_text(encoding='utf8')
    build=(REPORTS/'efinity_e6_compile.log').read_text(encoding='utf8')
    for stage in ('map','interface','pnr','pgm'):assert re.search(r'\b'+stage+r'\s*:\s*PASS',build),stage
    out=ROOT/'outflow';metrics=timing(out/'ti60f225_oob.timing.rpt')
    assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
    resources={};place=(out/'ti60f225_oob.place.rpt').read_text()
    for label in ('XLRs','Memory Blocks','DSP Blocks'):
        m=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
        resources[label]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
    for suffix in ('timing.rpt','cdc.rpt','place.rpt','map.rpt','log','warn.log','err.log'):
        shutil.copy2(out/('ti60f225_oob.'+suffix),REPORTS/('e6_'+suffix))
    artifacts=[]
    for ext in ('bit','hex'):
        src=out/f'ti60f225_oob.{ext}';assert src.stat().st_size>0
        dest=ROOT/f'programming/ti60f225_oob_V10_E6_DVI.{ext}'
        assert not dest.exists() or sha(dest)==sha(src),'Refuse different published firmware overwrite'
        shutil.copy2(src,dest)
        artifacts.append(dict(path=dest.relative_to(ROOT).as_posix(),sha256=sha(dest),bytes=dest.stat().st_size))
    archive=ROOT/'reference/e5_firmware';archive.mkdir(exist_ok=True)
    for p in (ROOT/'programming').iterdir():
        if p.is_file() and '_E6_' not in p.name:
            dest=archive/p.name
            assert p.resolve().is_relative_to(ROOT) and dest.resolve().is_relative_to(ROOT)
            assert not dest.exists() or sha(dest)==sha(p)
            if not dest.exists():shutil.move(str(p),str(dest))
    stats=tests['tmds_vectors']
    report=f'''# E6D 实际验证记录

状态：纯黑白 M2 输出的编码替换候选已生成，实板失锁是否消失尚待确认。

实板输入证据是用户反馈同一 E5 固件中 M7 稳定、M2 仍黑屏。未在电脑端复现模拟电气失锁，不宣称原加密编码器已经证实有 bug。

本版只把最终视频编码实例换为板卡随附、可检查的 DVI/TMDS 编码，并把 HUD 改为 E6D。编码主体保留资料原件与版权声明，仅重命名模块；三通道包装器保持 lane0 蓝/HS/VS、lane1 绿、lane2 红。视频每拍一个像素，RGB 和同步对齐。没有 HDMI 音频/数据岛/AVI 信息帧。

M2 显示码值仍是 000000/FFFFFF。边缘处理、预处理、NMS、连接、行缓存、控制器、M7、原色彩和 gamma 路径字节不变；相机、DDR、PLL、复位、串化器、输出取反、驱动设置和 SDC 保留。原 E5 发布文件按 SHA256 核验保留。

本轮实际运行 8 组检查全部 PASS。独立 TMDS 模型逐拍比较 {stats['cycles']} 拍，包含 {stats['exhaustive_state_byte_pairs']} 个可达直流平衡状态与字节的穷尽组合，可达状态 {stats['reachable_disparities']}，有效像素 {stats['active_pixels']}，控制/消隐输入拍 {stats['control_cycles']}，复位输入拍 {stats['midstream_reset_cycles']}。另检查真实处理核心 M2/M7 等价、八页/原七页控制、PRE 长按、E6D HUD、欠载和视频恢复。

工程 80 个源文件及公开接口检查 PASS；8 个元数据案例 PASS。加密 IP 的接口占位只用于工程结构检查，不作为原编码器功能仿真。

Efinity 2026.1.132 的 map/interface/pnr/pgm 均 PASS。最小已报告 setup +{metrics['min_setup_ns']:.3f} ns，hold +{metrics['min_hold_ns']:.3f} ns，HDMI 像素时钟域 setup +{metrics['hdmi_setup_ns']:.3f} ns。CDC 无 synchronizer 警告，74.25/148.5 MHz 双向时钟关系仍检查。该报告不替代高速输出眼图、实际供电或外部 IO 签核。

实际资源：XLR {resources['XLRs']['used']}/{resources['XLRs']['available']}，RAM {resources['Memory Blocks']['used']}/{resources['Memory Blocks']['available']}，DSP {resources['DSP Blocks']['used']}/{resources['DSP Blocks']['available']}。

烧录 programming/ti60f225_oob_V10_E6_DVI.bit 后确认 E6D，在此前易失锁场景保持 M2/T58/PRE0，观察约5分钟并重复手/人脸进出。随后看 M7、M0。是否仍出现显示器无信号是关键结果。即使这版稳定，替换同时改变编码、消隐、资源和布局，不能仅凭结果宣布原 IP 有逻辑错误。若仍只有 M2 失败，应进一步测量码型相关物理输出/电源/时钟，不能靠阈值调整解决失锁。

旧 E3/E4/E5 报告为继承历史，不计入本轮新测试。详细操作见 docs/V10_E6_DVI.md。
'''
    (REPORTS/'V10_E6_VALIDATION.md').write_text(report,encoding='utf8')
    sources=[e.get('name') for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter() if e.tag.endswith('design_file')]
    files=[]
    for folder in ('rtl','ip','ooc','scripts','sim','reference','docs','programming','reports'):
        for p in (ROOT/folder).rglob('*'):
            rel=p.relative_to(ROOT)
            if p.is_file() and not any(part.startswith('build') or part=='__pycache__' for part in rel.parts[:-1]):
                if p.name not in ('e6_release_manifest.json','e6_package_verification.json','e6_finalization.log'):files.append(p)
    files += [p for p in ROOT.iterdir() if p.is_file() and not p.name.startswith('interfaces_direct.')]
    manifest=dict(revision='V10-E6',status='DVI_ENCODER_REPLACEMENT_CANDIDATE_AWAITING_BOARD',
        collected_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        timing=metrics,resources=resources,artifacts=artifacts,verification=tests,scope=scope,
        source_sha256={n:sha(ROOT/n) for n in sources},
        sha256={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(files))})
    mp=REPORTS/'e6_release_manifest.json';mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    dest=ROOT.parent/'packages';dest.mkdir(exist_ok=True)
    package=dest/'ti60f225_oob_V10_E6_dvi_candidate.zip';assert not package.exists(),'Preserve published package'
    with zipfile.ZipFile(package,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n in sorted(manifest['sha256']):z.write(ROOT/n,'ti60f225_oob/'+n)
        z.write(mp,'ti60f225_oob/reports/e6_release_manifest.json')
    with zipfile.ZipFile(package) as z:
        assert z.testzip() is None
        for n,h in manifest['sha256'].items():assert hashlib.sha256(z.read('ti60f225_oob/'+n)).hexdigest()==h
        count=len(z.namelist())
    digest=sha(package);package.with_suffix('.sha256').write_text(digest+'  '+package.name+'\n')
    result=dict(status='PASS',path=str(package),sha256=digest,members=count,bytes=package.stat().st_size,
        CRC='PASS',member_sha256='PASS',board_fault='AWAITING BOARD CONFIRMATION')
    (REPORTS/'e6_package_verification.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
