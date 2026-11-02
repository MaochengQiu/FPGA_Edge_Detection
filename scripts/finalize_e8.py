from pathlib import Path
import datetime,hashlib,json,re,shutil,xml.etree.ElementTree as ET,zipfile
from finalize_e3 import timing
from check_e8_scope import main as check_scope

ROOT=Path(__file__).resolve().parents[1];OLD=ROOT.parents[1]/'v10-e7-quality/ti60f225_oob'
REPORTS=ROOT/'reports';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def hierarchy(path):
    result={};stack=[]
    for line in path.read_text().splitlines():
        cells=line.split('|')
        if len(cells)<5:continue
        match=re.match(r'^(\s*)\+(.+?)\s*$',cells[1])
        if not match:continue
        level=len(match[1]);name=match[2]
        while stack and stack[-1][0]>=level:stack.pop()
        stack.append((level,name));key='/'.join(n for _,n in stack)
        result[key]=dict(xlr_estimate=float(re.match(r'\s*([\d.]+)',cells[2])[1]),
            RAM=int(re.match(r'\s*(\d+)',cells[3])[1]),DSP=int(re.match(r'\s*(\d+)',cells[4])[1]))
    return result

def main():
    scope=check_scope()
    unit=json.loads((REPORTS/'e8_unit_verification.json').read_text())
    core=json.loads((REPORTS/'e8_core_verification.json').read_text())
    assert unit['status']=='PASS' and len(unit['tests'])==19
    assert core['status']=='PASS' and len(core['tests'])==7
    assert 'E8 UNIT PASS: 19' in (REPORTS/'e8_units.log').read_text(encoding='utf8')
    assert 'E8 CORE VERIFICATION PASS: 7' in (REPORTS/'e8_core.log').read_text(encoding='utf8')
    project=json.loads((REPORTS/'project_checks.json').read_text())
    assert project['public_interface_elaboration']=='PASS' and project['source_files']==81
    assert 'Project metadata regression PASS: 8 cases' in (REPORTS/'e8_structure.log').read_text(encoding='utf8')
    build=(REPORTS/'efinity_e8_compile.log').read_text(encoding='utf8')
    for stage in ('map','interface','pnr','pgm'):assert re.search(r'\b'+stage+r'\s*:\s*PASS',build),stage
    out=ROOT/'outflow';metrics=timing(out/'ti60f225_oob.timing.rpt')
    assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
    resources={};place=(out/'ti60f225_oob.place.rpt').read_text()
    for label in ('XLRs','Memory Blocks','DSP Blocks'):
        m=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
        resources[label]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
    baseline=json.loads((OLD/'reports/e7_release_manifest.json').read_text(encoding='utf8'))
    before=baseline['resources']
    assert resources['XLRs']['used']<before['XLRs']['used']
    assert resources['Memory Blocks']['used']<before['Memory Blocks']['used']
    for suffix in ('timing.rpt','cdc.rpt','place.rpt','hier_util.rpt','map.rpt','log','warn.log','err.log'):
        shutil.copy2(out/('ti60f225_oob.'+suffix),REPORTS/('e8_'+suffix))
    shutil.copy2(OLD/'outflow/ti60f225_oob.hier_util.rpt',REPORTS/'e7_baseline_hier_util.rpt')
    shutil.copy2(OLD/'reports/e7_place.rpt',REPORTS/'e7_baseline_place.rpt')
    h0=hierarchy(REPORTS/'e7_baseline_hier_util.rpt');h1=hierarchy(REPORTS/'e8_hier_util.rpt')
    keys=['edge_processing/original_alignment','edge_processing/nms_alignment',
        'edge_processing/link_alignment','edge_processing/preprocess/bypass_center',
        'edge_processing/preprocess/ctl_center','edge_processing/linking/timing','inst_gamma_correction']
    breakdown={k:dict(before=h0['ti60f225_oob_top/'+k],after=h1['ti60f225_oob_top/'+k]) for k in keys}
    comparison=dict(status='PASS',baseline='published E7',before=before,after=resources,
        saved={k:before[k]['used']-resources[k]['used'] for k in resources},
        free={k:resources[k]['available']-resources[k]['used'] for k in resources},
        timing_before=baseline['timing'],timing_after=metrics,module_hierarchy_estimates=breakdown,
        warning='Hierarchy XLR estimates are not interchangeable with placement totals; physical board stability remains unverified')
    (REPORTS/'e8_resource_comparison.json').write_text(json.dumps(comparison,indent=2))
    artifacts=[]
    for ext in ('bit','hex'):
        src=out/f'ti60f225_oob.{ext}';assert src.stat().st_size>0
        dest=ROOT/f'programming/ti60f225_oob_V10_E8_Resource.{ext}'
        assert not dest.exists() or sha(dest)==sha(src),'Refuse different published firmware overwrite'
        shutil.copy2(src,dest)
        artifacts.append(dict(path=dest.relative_to(ROOT).as_posix(),sha256=sha(dest),bytes=dest.stat().st_size))
    archive=ROOT/'reference/e7_firmware';archive.mkdir(exist_ok=True)
    for p in (ROOT/'programming').iterdir():
        if p.is_file() and '_E8_' not in p.name:
            dest=archive/p.name
            assert p.resolve().is_relative_to(ROOT) and dest.resolve().is_relative_to(ROOT)
            assert not dest.exists() or sha(dest)==sha(p)
            if not dest.exists():shutil.move(str(p),str(dest))
    lines=['# E8R 资源优化：实际验证记录','',
        '状态：资源优化、离线等价检查与实际编译完成；尚未进行本版实板稳定性确认。原 E7 发布文件按SHA256核验保留。','',
        '## 实际资源','',
        '| 资源 | E7已用 | E8已用 | 节省 | E8空闲 |','|---|---:|---:|---:|---:|']
    for k in resources:
        lines.append(f'| {k} | {before[k]["used"]}/{before[k]["available"]} ({before[k]["percent"]}) | {resources[k]["used"]}/{resources[k]["available"]} ({resources[k]["percent"]}) | {comparison["saved"][k]} | {comparison["free"][k]} |')
    lines+=['','以上为实际最终布局报告。DSP减少由本次综合/布局映射给出，没有改变灰度或梯度算术。以下为层级分布估算，用于定位节省来源。','',
        '| 模块 | E7 RAM块 | E8 RAM块 | E7 XLR估算 | E8 XLR估算 |','|---|---:|---:|---:|---:|']
    for k,v in breakdown.items():
        a,b=v['before'],v['after'];lines.append(f'| {k} | {a["RAM"]} | {b["RAM"]} | {a["xlr_estimate"]:g} | {b["xlr_estimate"]:g} |')
    lines+=['','三条主要对齐链的RAM块从83降到47，其他长延迟链继续节省，Gamma原初始ROM块不再需要。Gamma从动态寄存器数组改为固定曲线查表，实际综合为小规模逻辑，没有新增三路大RAM。','',
        '## 保持内容与差异','',
        '只修改 img_delay、gamma_correction、顶层HUD参数和HUD版本文字四个RTL文件。E7处理核心、滤波权重、PRE含义、NMS/连接门槛、阈值比例、图像分辨率、色彩增益、M2/M7码值、Gamma曲线文件、DDR与FIFO深度、相机、E6编码器、PLL、引脚和SDC均保持。',
        '核心延迟仍为6*HTOTAL+61，1080p为13261拍；未新增帧缓存、识别功能或额外处理延迟。',
        '首次初始化是一个明确例外：旧Gamma逐项填充寄存器表时，未填项的输出未定义；新ROM配置后立即确定。检查对新ROM每拍核对独立曲线模型，对旧版已定义RGB逐拍比较，并要求首次1032拍装载后及后续复位全过程相等。不能把未定义值当成规定像素，也不声称初始X与新值按位相同。','',
        '## 本轮实际检查','',
        '19组单元配置PASS：16种延迟位宽/深度（含2048/2049/2050/4097/4098边界、1字尾块、真实2205/4404/4432/6621参数和13261拍长延迟），回绕、预热及复位逐拍对照冻结E7；3组Gamma覆盖8/10位、2P2/2P0两种曲线，曲线、RGB、空白和同步逐拍匹配。',
        '7组核心/功能配置PASS：冻结完整E7边缘RTL的双核心对照，小图32帧覆盖8页×4种PRE；实际1920宽/HT2200的3帧覆盖M2/M3/M7和真实分块路径，中途复位。每拍比较RGB、DE/HS/VS、幅值、边缘与SOF；另检查八页控制、PRE长按、E8R HUD、欠载、视频恢复。',
        '81个源文件的结构和公开接口检查PASS，8个元数据案例PASS。旧E7的48图报告为历史，本轮没有将其冒充新跑结果。Gamma与完整核心原始日志及机器可读报告均在reports/e8_*。','',
        '## 实际编译与时序','',
        f'Efinity2026.1.132 map/interface/pnr/pgm均PASS。全设计最小已报告setup +{metrics["min_setup_ns"]:.3f} ns，hold +{metrics["min_hold_ns"]:.3f} ns；HDMI像素时钟域setup +{metrics["hdmi_setup_ns"]:.3f} ns，E7为+{baseline["timing"]["hdmi_setup_ns"]:.3f} ns。',
        'HDMI域余量改善不代表所有路径都改善：全设计最小setup与HDMI域数值不同。CDC无synchronizer警告，视频74.25/148.5MHz双向关系仍检查。SDC未删改；既有未使用接口/端口提示保留，静态结果不替代外部IO/供电/信号质量签核。','',
        '## 实板确认','',
        '烧录programming/ti60f225_oob_V10_E8_Resource.bit，确认E8R。默认仍M3/T50/PRE2。沿用E7同场景、同PRE、同T比较M2/M3/M7、冻结/恢复与切页；应保持原画质，继续观察是否有新的错位或失锁。资源变化会改变布局，当前不宣称实板稳定性已经提升。原E7保留供回退。','',
        '本次腾出的资源为后续小区域几何识别提供空间，具体新功能仍需独立预算和编译；本版没有增加识别。详见docs/V10_E8_RESOURCE.md。']
    (REPORTS/'V10_E8_VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    sources=[e.get('name') for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter() if e.tag.endswith('design_file')]
    files=[]
    for folder in ('rtl','ip','ooc','scripts','sim','reference','docs','programming','reports'):
        for p in (ROOT/folder).rglob('*'):
            rel=p.relative_to(ROOT)
            if p.is_file() and not any(part.startswith('build') or part=='__pycache__' for part in rel.parts[:-1]):
                if p.name not in ('e8_release_manifest.json','e8_package_verification.json'):files.append(p)
    files += [p for p in ROOT.iterdir() if p.is_file() and not p.name.startswith('interfaces_direct.')]
    manifest=dict(revision='V10-E8',status='RESOURCE_OPTIMIZATION_EQUIVALENCE_PASS_AWAITING_BOARD',
        collected_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        timing=metrics,resources=resources,comparison=comparison,artifacts=artifacts,unit_verification=unit,
        core_verification=core,scope=scope,source_sha256={n:sha(ROOT/n) for n in sources},
        sha256={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(files))})
    mp=REPORTS/'e8_release_manifest.json';mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    dest=ROOT.parent/'packages';dest.mkdir(exist_ok=True)
    package=dest/'ti60f225_oob_V10_E8_resource_candidate.zip';assert not package.exists(),'Preserve published package'
    with zipfile.ZipFile(package,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n in sorted(manifest['sha256']):z.write(ROOT/n,'ti60f225_oob/'+n)
        z.write(mp,'ti60f225_oob/reports/e8_release_manifest.json')
    with zipfile.ZipFile(package) as z:
        assert z.testzip() is None
        for n,h in manifest['sha256'].items():assert hashlib.sha256(z.read('ti60f225_oob/'+n)).hexdigest()==h
        count=len(z.namelist())
    digest=sha(package);package.with_suffix('.sha256').write_text(digest+'  '+package.name+'\n')
    result=dict(status='PASS',path=str(package),sha256=digest,members=count,bytes=package.stat().st_size,
        CRC='PASS',member_sha256='PASS',board='AWAITING PHYSICAL CONFIRMATION')
    (REPORTS/'e8_package_verification.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
