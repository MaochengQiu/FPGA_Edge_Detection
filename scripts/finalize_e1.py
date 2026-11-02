"""Collect two real E1 builds and measurable A/B results, never promote C2."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from check_e1_scope import check,shape
ROOT=Path(__file__).resolve().parents[1];AB=ROOT/'work/sobel'
scope=check()
tests=json.loads((ROOT/'reports/verification.json').read_text())
assert len(tests)==31 and all(t['status']=='PASS' for t in tests)
assert 'ALL REGRESSIONS PASSED' in (ROOT/'reports/rtl_regression_v10_e1.log').read_text(encoding='utf-8-sig')
algo=json.loads((ROOT/'reports/e1_algorithm_verification.json').read_text())
assert algo['direction']['status']=='PASS' and len(algo['nms_unit'])==14 and all(t['status']=='PASS' for t in algo['nms_unit'])
assert algo['image_ab']['status']=='PASS' and algo['image_ab']['rtl_images']==18
assert 'E1 ALGORITHM PASS' in (ROOT/'reports/e1_algorithm.log').read_text(encoding='utf-8-sig')
assert 'E1 EQUIVALENCE PASS' in (ROOT/'sim/build/tb_e1_equivalence_run.log').read_text()
project=json.loads((ROOT/'reports/project_checks.json').read_text())
assert project['public_interface_elaboration']=='PASS' and project['source_files']==75
assert all(x['status']=='PASS' for x in json.loads((ROOT/'reports/project_structure_regression.json').read_text()))
assert shape(ET.parse(ROOT/'ti60f225_oob.xml').getroot())==shape(ET.parse(AB/'ti60f225_oob.xml').getroot())
sources=[e.get('name') for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter() if e.tag.rsplit('}',1)[-1]=='design_file']
sources+=['ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem']
for name in sources:
    if name=='ti60f225_oob.xml':continue
    a=(ROOT/name).read_bytes();b=(AB/name).read_bytes()
    if name=='rtl/ti60f225_oob_top.v':
        b=b.replace(b"parameter E1_NMS_ENABLE = 1'b0",b"parameter E1_NMS_ENABLE = 1'b1")
    assert a==b,'A/B build differs beyond enable parameter: '+name

def rows(s):
    return [dict(launch=m[0],capture=m[1],constraint_ns=float(m[2]),slack_ns=float(m[3])) for m in
        re.findall(r'^\s*(\S+)\s+(\S+)\s+([\d.-]+)\s+([\d.-]+)\s+\(R-R\)',s,re.M)]
variants={};files=[ROOT/n for n in sources]
latest_rtl=max((ROOT/n).stat().st_mtime for n in sources if Path(n).suffix in ('.v','.sv','.sdc'))
for log in ('verification.json','e1_algorithm_verification.json','project_checks.json'):
    assert (ROOT/'reports'/log).stat().st_mtime>=latest_rtl,'Stale check: '+log
for key,root,label in (('nms',ROOT,'NMS'),('sobel',AB,'Sobel')):
    out=root/'outflow'
    flow=(ROOT/f'reports/efinity_v10_e1_{key}_compile.log').read_text(encoding='utf-8-sig')
    for stage in ('map','interface','pnr','pgm'):assert re.search(r'\b'+stage+r'\s*:\s*PASS',flow),(key,stage)
    timing=(out/'ti60f225_oob.timing.rpt').read_text()
    setup=rows(timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min)',1)[0])
    hold=rows(timing.split('Hold (Min) Clock Relationship',1)[1].split('NOTE:',1)[0])
    assert setup and hold and min(r['slack_ns'] for r in setup+hold)>=0,(key,'negative timing')
    for a,b in (('vid_clk_dvi2','hdmi_tx_slow_clk'),('hdmi_tx_slow_clk','vid_clk_dvi2')):
        assert any(r['launch']==a and r['capture']==b for r in setup)
    assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
    place=(out/'ti60f225_oob.place.out').read_text(errors='replace')
    assert not re.search(r'No pins matched[^\n]*(video_health|edge_read_error_sync)',place)
    for ext in ('bit','hex'):
        src=out/f'ti60f225_oob.{ext}';assert src.stat().st_size>100000
        assert all((root/n).stat().st_mtime<=src.stat().st_mtime+(2 if n=='ti60f225_oob.xml' else 0) for n in sources),'Stale '+key
        dest=ROOT/f'programming/ti60f225_oob_V10_E1_{label}.{ext}'
        if dest.exists():assert dest.read_bytes()==src.read_bytes(),'Preserve E1 artifact'
        else:shutil.copy2(src,dest)
        files.append(dest)
    for suffix,name in (('timing.rpt','timing.rpt'),('cdc.rpt','cdc.rpt'),('place.rpt','resources.rpt'),
        ('map.out','synthesis.log'),('place.out','place_route.log'),('pgm.out','bitstream.log')):
        shutil.copy2(out/f'ti60f225_oob.{suffix}',ROOT/f'reports/e1_{key}_{name}')
    resources=(out/'ti60f225_oob.place.rpt').read_text()
    resource_lines=[s for s in resources.splitlines() if re.match(r'^(XLRs|Memory Blocks|DSP Blocks):',s)]
    hdmi=next(r for r in setup if r['launch']==r['capture']=='hdmi_tx_slow_clk')
    variants[key]=dict(nms_enable=key=='nms',strict_ties=False,setup=setup,hold=hold,
        min_setup_ns=min(r['slack_ns'] for r in setup),min_hold_ns=min(r['slack_ns'] for r in hold),
        hdmi_setup_ns=hdmi['slack_ns'],resources=resource_lines,
        top_source_sha256=hashlib.sha256((root/'rtl/ti60f225_oob_top.v').read_bytes()).hexdigest())
shutil.copy2(ROOT/'reports/verification.json',ROOT/'reports/verification_e1.json')
metrics=algo['image_ab']['fixtures']
table='\n'.join(f'| {r["name"]} | {r["sobel"]["edge_pixels"]} | {r["nms"]["edge_pixels"]} | {r["sobel"]["solid_2x2"]} / {r["nms"]["solid_2x2"]} | {r["sobel"]["components_8"]} / {r["nms"]["components_8"]} |' for r in metrics)
times='\n'.join(f'| {k} | {v["hdmi_setup_ns"]:+.3f} | {v["min_setup_ns"]:+.3f} | {v["min_hold_ns"]:+.3f} |' for k,v in variants.items())
resources='\n\n'.join(k+':\n'+'\n'.join(v['resources']) for k,v in variants.items())
report=dict(revision='V10-E1',collected_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
    basis='Color-complete C2 series, C2.1 confirmed preset',scope=scope,regression_results=tests,
    algorithm_results=algo,builds=variants,clock_mhz=148.5,added_latency_cycles=2205,
    added_latency_us=2205/148.5,kernel_latency_cycles=6627,throughput='one pixel/clock',
    default='NMS on, plateau-preserving ties; high/low connectivity not merged',
    color='PH2 BGGR, gain 0x240/0x180/0x240 unchanged',
    hardware_validation='NOT RUN. No promotion to stable C2/C2.1',
    caveats='NMS output is subset of same-threshold Sobel; does not restore below-threshold contours; some two-pixel ties remain')
step=next(r for r in metrics if r['name']=='blurred_step')
validation=f'''# V10-E1 验证与交付记录

采集时间：{report['collected_at']}。独立实验目录，稳定 C2/C2.1 未覆盖，未自动烧录硬件。

## 修改文件

- 新增 `rtl/edge/gradient/img_nms.sv`：两行 RAM、四方向完整 11 位幅值 NMS、有效性、两级比较及两种平台策略。
- 修改 `rtl/edge/top/img_pipeline.sv`：保留原判定，加入方向寄存、NMS 及 RGB/灰度/幅值/配置/同步的等长延迟。
- 修改 `rtl/ti60f225_oob_top.v`：只增加 NMS 开关/平台参数并传给核心和 HUD；归一化后其余连线与基准逐字相同。
- 修改 `rtl/edge/compose/edge_final_hud.sv`：E1N/E1S 路径标识。`ti60f225_oob.xml` 只新增一个 design_file。
- 测试/脚本新增 NMS 向量、方向边界、冻结 C2 核心对照及实际 RTL 固定图测试。接口数量检查改为 75 源/26 自定义模块。

冻结清单校验通过：白平衡、PH2、Debayer、RGB 精度、Sobel 算术、预处理、合成、相机初始化、DDR/MIPI/HDMI/PLL、复位及 SDC 均未改。详细 patch 与清单见 `e1_changes.patch`、`e1_scope.json`。

## 实际验证

- 31 组完整回归全部通过，含原模式/阈值、按键、色彩、冻结、FIFO/DDR、异常恢复及连续同步。
- 冻结 C2 参考只重命名模块用于仿真，E1S 在补偿新增延迟后与其逐像素完全相同；E1N/E1S 同步相同，M0/M1/M5/M6 内容一致，M3 左原图不变，NMS 不新增原阈值未接受的边缘。
- 17307 个方向测试覆盖象限/轴/满量程及角度分界。固定点和浮点分档差异只在分界附近，最大角度距离 {algo['direction']['maximum_boundary_difference_deg']:.6f}°，不是梯度计算截断。
- 14 组 NMS 网格/策略测试，共 {sum(r['samples'] for r in algo['nms_unit'])} 个采样时钟；尺寸从 1×1 到 1920 宽和 1080 高，覆盖平台、有效性空洞、边界和连续帧，与独立参考一致。
- 9 张固定输入分别运行两条实际 RTL 路径（18 个输出），同为 T=24、预处理旁路；每个像素及 DE/HS/VS 都与参考核对。源 PNG、SHA256 和来源保存在 `reference/e1_inputs`。
- 75 个源文件接口检查和 8 项工程结构检查通过。加密 IP 在开源接口检查中用公开端口占位，实际 Efinity 综合使用原加密源。

## 同阈值 A/B 的实际结果

比较图为 `e1_ab/comparison.png`，列顺序：固定输入、M5 原始幅值、Sobel T=24、默认 NMS T=24。真实人像来自公开测试照片；杯纹、PCB、文字、棋盘和运动是合成测试，不能冒充实板画面。

| 输入 | Sobel 白点 | NMS 白点 | 实心2×2块 Sobel/NMS | 8连通分量 Sobel/NMS |
|---|---:|---:|---:|---:|
{table}

这些是描述性计数，白点少不等于 Precision 高，分量多也不能单独判定实际噪声。没有人工真值，不报告 Precision/Recall/F1，也不宣称真实弱轮廓召回提高。NMS 不会把低于同一阈值的响应变成边缘。

已知几何边界的合成模糊阶跃中，原 8 像素宽响应缩至默认策略 2 像素，横向平均距离从 {step['known_step_mean_x_error_px']['sobel']:.1f} px 到 {step['known_step_mean_x_error_px']['nms']:.1f} px；该结论仅属于这个合成测试。严格策略可进一步细化，但在合成圆弧中使连通分量从 2 增至 37；默认平台策略保持为 2。PCB 默认策略仍有局部连接/孤立响应问题，不能宣称连续性与去噪已全部解决。

CPU 离线双阈值 24/12 与完整 8 连通泛洪实验通过：长弱链可连接强种子，独立弱岛被丢弃。它没有合入 RTL，本版不是完整 Canny。

## 编译、时序与资源

两种路径分别实际执行 Efinity map/interface/pnr/pgm，均须 PASS 后才收集固件。全部已报告 setup/hold 非负，相关视频时钟两向仍检查，CDC 无同步器警告。原未使用 JTAG/接口约束等提示仍在，不代表所有 IO 均已完整签核。

| 版本 | HDMI setup ns | 最小 setup ns | 最小 hold ns |
|---|---:|---:|---:|
{times}

```text
{resources}
```

完整编译/时序/CDC/资源报告以 `e1_nms_*`、`e1_sobel_*` 保存，编译总日志为 `efinity_v10_e1_*_compile.log`。两种构建除 enable 参数外所有输入源一致，配置/约束语义相同。E1 核心所有模式统一 6627 周期，较原增加 2205 周期，约 14.85 微秒，处理速率仍为一像素/周期。

## 交付与实板边界

实验默认固件 `programming/ti60f225_oob_V10_E1_NMS.bit`；对照 `programming/ti60f225_oob_V10_E1_Sobel.bit`。源码默认开启 NMS，严格平台规则默认关闭；开关都是编译参数，原按键不被占用。

尚需实板：真实纸杯/文字/PCB/五官的细节与噪声，圆弧/斜线连续性，M3 左右/M4 轮廓定位，M5 原样预览，运动延迟、长时间运行、切模式/调阈值及冻结恢复、HDMI 与 U/D/R/L/O。在用户确认前不替换稳定 C2/C2.1。操作见 `docs/V10_E1_NMS.md`。
'''
(ROOT/'reports/V10_E1_VALIDATION.md').write_text(validation,encoding='utf-8')
files += [ROOT/'README.md',ROOT/'docs/V10_E1_NMS.md',ROOT/'reports/V10_E1_VALIDATION.md',ROOT/'BUILD_NEW_FIRMWARE_REQUIRED.txt']
files += list((ROOT/'sim').glob('tb*.sv'))+[ROOT/'sim/reference/img_pipeline_c2_reference.sv']
files += [ROOT/f'scripts/{n}.py' for n in ('check_e1_scope','finalize_e1','package_e1','verify_e1','run_tests','check_project','project_structure','test_project_structure','prepare_e1_sobel_build')]
files += [f for d in ('reference/e1_baseline','reference/e1_inputs','reports/e1_ab') for f in (ROOT/d).rglob('*') if f.is_file()]
files += [ROOT/'reports/e1_algorithm_verification.json',ROOT/'reports/verification_e1.json']
report['sha256']={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in dict.fromkeys(files)}
(ROOT/'reports/v10_e1_release_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('V10-E1 FINAL PASS: 31 regression groups, 14 NMS grids, 18 RTL images, both actual builds; stable C2/C2.1 untouched')
for k,v in variants.items():print(k,'HDMI setup',v['hdmi_setup_ns'],'min hold',v['min_hold_ns'])
