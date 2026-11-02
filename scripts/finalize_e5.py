from pathlib import Path
import datetime,hashlib,json,re,shutil,subprocess,sys,xml.etree.ElementTree as ET,zipfile
from finalize_e3 import timing

ROOT=Path(__file__).resolve().parents[1];REPORTS=ROOT/'reports'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    subprocess.run([sys.executable,str(ROOT/'scripts/check_e5_scope.py')],check=True)
    result=json.loads((REPORTS/'e5_verification.json').read_text())
    assert result['status']=='PASS' and len(result['tests'])==7
    assert 'E5 VERIFICATION PASS' in (REPORTS/'e5_verification.log').read_text(encoding='utf8')
    structure=json.loads((REPORTS/'project_checks.json').read_text())
    assert structure['public_interface_elaboration']=='PASS' and structure['source_files']==78
    assert 'Project metadata regression PASS: 8 cases' in (REPORTS/'e5_structure.log').read_text(encoding='utf8')
    log=(REPORTS/'efinity_e5_compile.log').read_text(encoding='utf8')
    for stage in ('map','interface','pnr','pgm'):assert re.search(r'\b'+stage+r'\s*:\s*PASS',log)
    out=ROOT/'outflow';t=timing(out/'ti60f225_oob.timing.rpt')
    assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
    resources={};place=(out/'ti60f225_oob.place.rpt').read_text()
    for label in ('XLRs','Memory Blocks','DSP Blocks'):
        m=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
        resources[label]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
    for suffix in ('timing.rpt','cdc.rpt','place.rpt','map.rpt','log','warn.log','err.log'):
        shutil.copy2(out/('ti60f225_oob.'+suffix),REPORTS/('e5_'+suffix))
    artifacts=[]
    for extension in ('bit','hex'):
        source=out/f'ti60f225_oob.{extension}';assert source.stat().st_size>0
        dest=ROOT/f'programming/ti60f225_oob_V10_E5_Output_AB.{extension}'
        assert not dest.exists() or sha(dest)==sha(source),'Refuse different firmware overwrite'
        shutil.copy2(source,dest)
        artifacts.append(dict(path=dest.relative_to(ROOT).as_posix(),sha256=sha(dest),size=dest.stat().st_size))
    previous=ROOT/'reference/e4_firmware';previous.mkdir(exist_ok=True)
    for p in (ROOT/'programming').iterdir():
        if p.is_file() and '_E5_' not in p.name:
            dest=previous/p.name
            assert p.resolve().is_relative_to(ROOT) and dest.resolve().is_relative_to(ROOT)
            assert not dest.exists() or sha(dest)==sha(p)
            if not dest.exists():shutil.move(str(p),str(dest))
    lines=['# E5 输出数据对照：实际验证与排查结论','',
        '状态：同一固件 M2/M7 诊断实验已生成，实板黑屏根因尚未确认，不能称为修复。','',
        '用户反馈 E4T 固定测试图稳定，同一复杂场景主要 M2 黑屏，而 M3/M5 稳定。照片为 E4D/M2/T58/PRE0，C/B/S=30、U/D/R/L/O=0；这些不是黑屏瞬间的记录。','',
        '## 对“内存/算不过来”的检查','',
        'RTL 没有按边缘数量申请内存或排队处理。行缓存容量、地址推进、24 级局部图展开及一时钟一像素吞吐固定；M2/M3/M5 共用算法。因此没有发现“边缘多导致容量溢出/计算次数增加”的机制。',
        '不能由此排除内容相关的位翻转功耗、供电或时序问题。E4T 编译时许多计算被裁剪，其资源只有 XLR15367、RAM81；E4D 则是 XLR49818、RAM234。固定图稳定不是完整系统在相同负载下稳定的证明。','',
        '## 单一 bitstream 对照','',
        'M2 原 000000/FFFFFF 保留，M7 从同一边缘位映射为 000103/E0F0FF。NMS、连接、灰度、预处理、行缓存、分辨率、时钟、DDR、复位与原色彩增益均不改。M0～M6 编号保留，模式键新增循环 M7。',
        '这是输出码值实验，不是边缘增强。M2/M7 共用同一 FPGA 布局，避免两次编译的布局差异干扰比较；RGB 所造成的开关活动本身正是待区分变量。','',
        '## 本轮实际结果','',
        '7 组定向检查 PASS：M2/M7 双核心 12 帧逐像素对照（PRE0～3、T47/58/68）、64 次八页循环、原默认七页控制、PRE 长按、E5A/M7 HUD、欠载保持 UI、video_out 故障恢复。M2/M7 边缘判定、梯度幅值、DE/HS/VS 完全一致，只允许显示 RGB 差别。',
        '结构及公开接口检查 PASS；8 个元数据案例 PASS。没有将旧 32 组或旧 52 图结果作为 E5 新跑结果。',
        f'Efinity 2026.1.132 map/interface/pnr/pgm 均 PASS；最小已报告 setup +{t["min_setup_ns"]:.3f} ns，hold +{t["min_hold_ns"]:.3f} ns，HDMI setup +{t["hdmi_setup_ns"]:.3f} ns。CDC 无 synchronizer 警告。',
        f'实际资源 XLR {resources["XLRs"]["used"]}/60800、RAM {resources["Memory Blocks"]["used"]}/256、DSP {resources["DSP Blocks"]["used"]}/160；SDC/外设设置不变，视频相关时钟双向关系仍检查。','',
        'E4D 最紧视频路径报告为比较显示行 RAM 到 gamma_bdata，setup 余量 +0.315 ns；E5 相应最紧路径余量 +0.180 ns，仍为正。这是静态报告，不等于已证明该路径在实板出错，更不能替代外部 IO/电气验证。','',
        '## 实板判定','',
        '保持复杂场景、T58、PRE0；比较同一固件的 M2 与 M7。不同时换线、调阈值或换预处理。M7 稳定而 M2 失锁时，优先缩小到数据相关输出/编码/串化/电气/时序；两者都失锁则继续记录 HUD/无信号、U/D/R/L/O、K/LAST、V 和同场景 M3/M5。若两者都稳定，不能忽略重编译布线改变余量的可能。',
        '参考 docs/V10_E5_OUTPUT_AB.md。原 E4 全部发布文件按 SHA256 保留。本次只有顶层、控制器页数上限、合成器 M7 分支及 HUD 标识四个 RTL 文件变化。']
    (REPORTS/'V10_E5_VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    project=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
    sources=[e.get('name') for e in project.iter() if e.tag.endswith('design_file')]
    files=[]
    for name in ('rtl','ip','ooc','scripts','sim','reference','docs','programming','reports'):
        for p in (ROOT/name).rglob('*'):
            rel=p.relative_to(ROOT)
            if p.is_file() and not any(part.startswith('build') or part=='__pycache__' for part in rel.parts[:-1]):
                if p.name not in ('e5_release_manifest.json','e5_package_verification.json'):files.append(p)
    files += [p for p in ROOT.iterdir() if p.is_file() and not p.name.startswith('interfaces_direct.')]
    manifest=dict(revision='V10-E5',status='OUTPUT_CODEWORD_PROBE_NOT_A_CONFIRMED_FIX',
        collected_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        timing=t,resources=resources,artifacts=artifacts,verification=result,
        scope=json.loads((REPORTS/'e5_scope.json').read_text()),source_sha256={n:sha(ROOT/n) for n in sources},
        sha256={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(files))})
    mp=REPORTS/'e5_release_manifest.json';mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    dest=ROOT.parent/'packages';dest.mkdir(exist_ok=True)
    package=dest/'ti60f225_oob_V10_E5_output_ab.zip';assert not package.exists(),'Preserve published package'
    with zipfile.ZipFile(package,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n in sorted(manifest['sha256']):z.write(ROOT/n,'ti60f225_oob/'+n)
        z.write(mp,'ti60f225_oob/reports/e5_release_manifest.json')
    with zipfile.ZipFile(package) as z:
        assert z.testzip() is None
        for n,h in manifest['sha256'].items():assert hashlib.sha256(z.read('ti60f225_oob/'+n)).hexdigest()==h
        count=len(z.namelist())
    digest=sha(package);package.with_suffix('.sha256').write_text(digest+'  '+package.name+'\n')
    record=dict(status='PASS',path=str(package),sha256=digest,members=count,bytes=package.stat().st_size,
        CRC='PASS',member_sha256='PASS',root_cause='NOT YET CONFIRMED')
    (REPORTS/'e5_package_verification.json').write_text(json.dumps(record,indent=2))
    print(json.dumps(record,indent=2))

if __name__=='__main__':main()
