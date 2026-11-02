from pathlib import Path
import datetime,hashlib,json,re,shutil,xml.etree.ElementTree as ET,zipfile
from finalize_e3 import timing
from check_e7_scope import main as check_scope

ROOT=Path(__file__).resolve().parents[1];REPORTS=ROOT/'reports'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    scope=check_scope()
    tests=json.loads((REPORTS/'e7_verification.json').read_text())
    images=json.loads((REPORTS/'e7_image_verification.json').read_text())
    assert tests['status']=='PASS' and len(tests['tests'])==9
    assert images['status']=='PASS' and images['rtl_outputs']==48
    assert 'E7 FUNCTIONAL VERIFICATION PASS' in (REPORTS/'e7_verification.log').read_text(encoding='utf8')
    assert 'E7 IMAGE PASS 48 actual RTL outputs' in (REPORTS/'e7_images.log').read_text(encoding='utf8')
    structure=json.loads((REPORTS/'project_checks.json').read_text())
    assert structure['public_interface_elaboration']=='PASS' and structure['source_files']==81
    assert 'Project metadata regression PASS: 8 cases' in (REPORTS/'e7_structure.log').read_text(encoding='utf8')
    build=(REPORTS/'efinity_e7_compile.log').read_text(encoding='utf8')
    for stage in ('map','interface','pnr','pgm'):assert re.search(r'\b'+stage+r'\s*:\s*PASS',build),stage
    out=ROOT/'outflow';metrics=timing(out/'ti60f225_oob.timing.rpt')
    assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
    resources={};place=(out/'ti60f225_oob.place.rpt').read_text()
    for label in ('XLRs','Memory Blocks','DSP Blocks'):
        m=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
        resources[label]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
    for suffix in ('timing.rpt','cdc.rpt','place.rpt','map.rpt','log','warn.log','err.log'):
        shutil.copy2(out/('ti60f225_oob.'+suffix),REPORTS/('e7_'+suffix))
    artifacts=[]
    for ext in ('bit','hex'):
        src=out/f'ti60f225_oob.{ext}';assert src.stat().st_size>0
        dest=ROOT/f'programming/ti60f225_oob_V10_E7_Quality.{ext}'
        assert not dest.exists() or sha(dest)==sha(src),'Refuse different published firmware overwrite'
        shutil.copy2(src,dest)
        artifacts.append(dict(path=dest.relative_to(ROOT).as_posix(),sha256=sha(dest),bytes=dest.stat().st_size))
    archive=ROOT/'reference/e6_firmware';archive.mkdir(exist_ok=True)
    for p in (ROOT/'programming').iterdir():
        if p.is_file() and '_E7_' not in p.name:
            dest=archive/p.name
            assert p.resolve().is_relative_to(ROOT) and dest.resolve().is_relative_to(ROOT)
            assert not dest.exists() or sha(dest)==sha(p)
            if not dest.exists():shutil.move(str(p),str(dest))
    lines=['# E7Q 实际验证记录','',
        '状态：新滤波候选已生成，实板画质和偶发失锁仍待确认。用户已反馈 E6 黑屏频率明显降低但仍偶发；本轮不把该问题标为关闭。','',
        '## 实现与控制','',
        '默认 M3/T50/PRE2，PRE0 旁路、PRE1 中值3、PRE2 高斯5、PRE3 高斯3。PRE3 替换原锐化，便于同一固件比较两种平滑强度。M7 保留原输出码值诊断作用。',
        '高斯5是 [1,4,6,4,1] 外积/256，仅最后加128取整；中值与高斯3取共同5×5窗口的中心3×3。滤波模式排除3像素梯度边界。全部模式核心延迟 6*HTOTAL+61（1080p为13261拍），比E6增加2201拍约14.82微秒。',
        'NMS平台规则、方向图连接、三强种子门槛、低阈值ceil(T/2)和桥接保持。相机、DDR、颜色、gamma、E6编码器、复位、PLL、驱动、串化、引脚、SDC保持；原E6发布文件逐项SHA256核验保留。','',
        '## 实际离线结果','',
        '9组定向功能检查PASS：高斯5的4096组极值/脉冲/随机窗口；真实核心12帧PRE变化的M2/M7对照；8帧PRE变化的RGB逐拍延迟；默认PRE2/T50与64次八页循环；原控制；PRE长按；E7Q HUD；欠载；视频恢复。',
        '48个实际RTL图像输出（8输入×6配置），每个输出像素对照独立整数模型，每拍核对DE/HS/VS；81个源文件的接口/结构检查与8个元数据案例PASS。','',
        '下表仅是已知平坦合成区域的误响应像素，不是实板噪点、召回率或主观画质评分。','',
        '| 合成输入 | 旁路58 | 中值50 | 高斯3/T58 | 高斯5/T58 | 高斯5/T50 | 高斯5/T50严格NMS |',
        '|---|---:|---:|---:|---:|---:|---:|']
    labels=[v[0] for v in images['variants']]
    for row in images['fixtures']:
        if row['name'].startswith('flat_noise'):
            lines.append('| '+row['name']+' | '+' | '.join(str(row['variants'][v]['known_flat_false_pixels']) for v in labels)+' |')
    lines+=['','已知竖直阶跃的逐行覆盖，仅要求边界±3像素附近有输出，不是精确定位或完整Canny指标。','',
        '| 合成输入 | 旁路58 | 中值50 | 高斯3/T58 | 高斯5/T58 | 高斯5/T50 | 高斯5/T50严格NMS |',
        '|---|---:|---:|---:|---:|---:|---:|']
    for row in images['fixtures']:
        if row['name'].startswith('noisy_step'):
            lines.append('| '+row['name']+' | '+' | '.join(str(row['variants'][v]['known_boundary_rows_hit'])+'/'+str(row['variants'][v]['known_boundary_rows_total']) for v in labels)+' |')
    lines += ['',
        '本次固定输入的取舍：flat_noise_8 的已知平坦ROI误响应在高斯3/T58为21像素，在高斯5/T50为0；noisy_step_20在高斯5/T58只覆盖8/82行，降到T50后覆盖82/82行。该结果支持更强平滑后重新选阈值，不能拿原T58直接判断滤波无效。',
        '严格NMS下该弱竖边覆盖降到80/82行；公开人脸例的描述性端点数从非严格的71增至87、连通分量从65增至72。没有真实轮廓标注，不能由端点数单独判断正确性；因此没有将严格细化直接合入本次上板默认。','',
        '杯纹、文字和公开人脸图没有人工轮廓真值，只给出像素/连通性描述及 reports/e7_quality/comparison.png。平滑会减弱细字与弱纹理，不能保证所有弱边缘都比高斯3完整。',
        '严格NMS已作为第六列同输入对照验证，但未启用到上板版本；当前先让实板直接比较平滑强度，避免把细线减少误当作整体质量改善。','',
        '## 实际编译','',
        f'Efinity2026.1.132 map/interface/pnr/pgm均PASS；最小已报告setup +{metrics["min_setup_ns"]:.3f} ns，hold +{metrics["min_hold_ns"]:.3f} ns，HDMI像素时钟域setup +{metrics["hdmi_setup_ns"]:.3f} ns。CDC无synchronizer警告，视频74.25/148.5MHz双向关系仍检查。',
        f'XLR {resources["XLRs"]["used"]}/60800，RAM {resources["Memory Blocks"]["used"]}/256，DSP {resources["DSP Blocks"]["used"]}/160。静态报告不等于外部IO/信号质量签核。','',
        '## 上板比较','',
        '确认E7Q后固定同一场景和T50，比较PRE2（新高斯5）与PRE3（原高斯3）。选定PRE后再小范围试T46/50/54。46/50/54只是操作起点，并非实板优化结果。记录背景跳点、外轮廓、细字和弯线，也继续观察M2/M7是否失锁。',
        '旧E3～E6报告均是继承历史；本次只引用e7前缀新结果。详见docs/V10_E7_QUALITY.md。']
    (REPORTS/'V10_E7_VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    sources=[e.get('name') for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter() if e.tag.endswith('design_file')]
    files=[]
    for folder in ('rtl','ip','ooc','scripts','sim','reference','docs','programming','reports'):
        for p in (ROOT/folder).rglob('*'):
            rel=p.relative_to(ROOT)
            if p.is_file() and not any(part.startswith('build') or part=='__pycache__' for part in rel.parts[:-1]):
                if p.name not in ('e7_release_manifest.json','e7_package_verification.json'):files.append(p)
    files += [p for p in ROOT.iterdir() if p.is_file() and not p.name.startswith('interfaces_direct.')]
    manifest=dict(revision='V10-E7',status='QUALITY_FILTER_CANDIDATE_AWAITING_BOARD',
        collected_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        timing=metrics,resources=resources,artifacts=artifacts,verification=tests,images=images,scope=scope,
        source_sha256={n:sha(ROOT/n) for n in sources},
        sha256={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(files))})
    mp=REPORTS/'e7_release_manifest.json';mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    dest=ROOT.parent/'packages';dest.mkdir(exist_ok=True)
    package=dest/'ti60f225_oob_V10_E7_quality_candidate.zip';assert not package.exists(),'Preserve published package'
    with zipfile.ZipFile(package,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for n in sorted(manifest['sha256']):z.write(ROOT/n,'ti60f225_oob/'+n)
        z.write(mp,'ti60f225_oob/reports/e7_release_manifest.json')
    with zipfile.ZipFile(package) as z:
        assert z.testzip() is None
        for n,h in manifest['sha256'].items():assert hashlib.sha256(z.read('ti60f225_oob/'+n)).hexdigest()==h
        count=len(z.namelist())
    digest=sha(package);package.with_suffix('.sha256').write_text(digest+'  '+package.name+'\n')
    result=dict(status='PASS',path=str(package),sha256=digest,members=count,bytes=package.stat().st_size,
        CRC='PASS',member_sha256='PASS',real_board='AWAITING QUALITY AND STABILITY CONFIRMATION')
    (REPORTS/'e7_package_verification.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
