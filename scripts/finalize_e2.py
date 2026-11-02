"""Validate actual E2 builds/tests, then collect named experimental firmware."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from check_e2_scope import check,shape

ROOT=Path(__file__).resolve().parents[1]
AB=ROOT/'work/nms_release'

def read(name):return (ROOT/name).read_text(encoding='utf-8-sig')
def load(name):return json.loads(read(name))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def fresh(result,names):
    assert (ROOT/result).stat().st_mtime>=max((ROOT/n).stat().st_mtime for n in names),'Stale result: '+result
def rows(s):
    return [dict(launch=m[0],capture=m[1],constraint_ns=float(m[2]),slack_ns=float(m[3])) for m in
        re.findall(r'^\s*(\S+)\s+(\S+)\s+([\d.-]+)\s+([\d.-]+)\s+\(R-R\)',s,re.M)]

scope=check()
tests=load('reports/verification.json')
assert len(tests)==32 and all(t['status']=='PASS' for t in tests)
reglog=read('reports/rtl_regression_v10_e2.log')
for marker in ('ALL REGRESSIONS PASSED','E1 EQUIVALENCE PASS','E2 EQUIVALENCE PASS',
    'PAIR_EDGE=0','PAIR_EDGE=1','MODE/THRESHOLD PASS'):
    assert marker in reglog,marker
local=load('reports/e2_local_verification.json')
assert local['directed']['status']=='PASS' and len(local['units'])==14
assert all(t['status']=='PASS' for t in local['units'])
assert 'E2 LOCAL VERIFICATION PASS' in read('reports/e2_local.log')
images=load('reports/e2_image_verification.json')
assert images['status']=='PASS' and images['rtl_outputs']==39 and len(images['fixtures'])==13
assert images['high']==50 and images['low']==25 and images['min_seeds']==3 and images['direction_constrained']
assert 'E2 IMAGE VERIFICATION PASS' in read('reports/e2_images.log')
for label in ('N24','N50','L50'):
    assert 'E2 IMAGE PASS' in read('reports/e2_image_'+label+'.log')
noise=[r for r in images['fixtures'] if r['name'].startswith('flat_noise_')]
assert len(noise)==4
for r in noise:
    n=r['known_background_false_pixels'];assert n['L50']<=n['N50']
weak=next(r for r in images['fixtures'] if r['name']=='weak_band')
assert weak['known_vertical_band_coverage']==dict(N24=3,N50=2,L50=3)
project=load('reports/project_checks.json')
assert project['public_interface_elaboration']=='PASS' and project['source_files']==77 and project['custom_modules']==28
structures=load('reports/project_structure_regression.json')
assert len(structures)==8 and all(t['status']=='PASS' for t in structures)
sources=[e.get('name') for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter()
    if e.tag.rsplit('}',1)[-1]=='design_file']
sources+=['ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem']
rtl=[n for n in sources if Path(n).suffix in ('.sv','.v','.sdc')]
fresh('reports/verification.json',rtl+['scripts/run_tests.py','sim/tb_composer_mirror.sv',
    'sim/tb_e1_equivalence.sv','sim/tb_e2_equivalence.sv'])
fresh('reports/e2_image_verification.json',rtl+['scripts/e2_model.py','scripts/verify_e2_images.py','sim/tb_e2_image.sv'])
fresh('reports/project_checks.json',rtl)
fresh('reports/e2_local_verification.json',[
    'rtl/edge/gradient/img_edge_link.sv','rtl/edge/video/img_window5x5.sv','rtl/edge/video/img_coords.sv',
    'rtl/edge/video/img_delay.sv','sim/tb_local_link.sv','scripts/verify_e2.py','scripts/e2_model.py'])

assert shape(ET.parse(ROOT/'ti60f225_oob.xml').getroot())==shape(ET.parse(AB/'ti60f225_oob.xml').getroot())
for name in sources:
    if name=='ti60f225_oob.xml':continue
    a=(ROOT/name).read_bytes();b=(AB/name).read_bytes()
    if name=='rtl/ti60f225_oob_top.v':
        old=b"parameter E2_LINK_ENABLE = 1'b0"
        assert b.count(old)==1
        b=b.replace(old,b"parameter E2_LINK_ENABLE = 1'b1")
    assert a==b,'A/B differs beyond E2_LINK_ENABLE: '+name

variants={}
(ROOT/'programming').mkdir(exist_ok=True)
(ROOT/'reference/e2_variants').mkdir(exist_ok=True)
for key,root,label in (('link',ROOT,'Link'),('nms',AB,'NMS')):
    out=root/'outflow'
    flow=read('reports/efinity_v10_e2_'+key+'_compile.log')
    for stage in ('map','interface','pnr','pgm'):
        assert re.search(r'\b'+stage+r'\s*:\s*PASS',flow),(key,stage)
    timing=(out/'ti60f225_oob.timing.rpt').read_text()
    setup=rows(timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min)',1)[0])
    hold=rows(timing.split('Hold (Min) Clock Relationship',1)[1].split('NOTE:',1)[0])
    assert setup and hold and min(r['slack_ns'] for r in setup+hold)>=0,(key,'timing')
    for a,b in (('vid_clk_dvi2','hdmi_tx_slow_clk'),('hdmi_tx_slow_clk','vid_clk_dvi2')):
        assert any(r['launch']==a and r['capture']==b for r in setup),(key,a,b)
    assert 'No Synchronizer warnings to report.' in (out/'ti60f225_oob.cdc.rpt').read_text()
    place=(out/'ti60f225_oob.place.out').read_text(errors='replace')
    assert not re.search(r'No pins matched[^\n]*(video_health|edge_read_error_sync)',place)
    firmware={}
    for ext in ('bit','hex'):
        src=out/f'ti60f225_oob.{ext}'
        assert src.stat().st_size>100000
        for n in sources:
            allowance=2 if n=='ti60f225_oob.xml' else 0
            assert (root/n).stat().st_mtime<=src.stat().st_mtime+allowance,'Stale '+key+': '+n
        dest=ROOT/f'programming/ti60f225_oob_V10_E2_{label}.{ext}'
        if dest.exists():assert dest.read_bytes()==src.read_bytes(),'Preserve existing E2 artifact'
        else:shutil.copy2(src,dest)
        firmware[ext]=dict(path=dest.relative_to(ROOT).as_posix(),sha256=sha(dest),bytes=dest.stat().st_size)
    for suffix,name in (('timing.rpt','timing.rpt'),('cdc.rpt','cdc.rpt'),('place.rpt','resources.rpt'),
        ('map.out','synthesis.log'),('place.out','place_route.log'),('pgm.out','bitstream.log')):
        shutil.copy2(out/f'ti60f225_oob.{suffix}',ROOT/f'reports/e2_{key}_{name}')
    resources=(out/'ti60f225_oob.place.rpt').read_text()
    resource_lines=[s for s in resources.splitlines() if re.match(r'^(XLRs|Memory Blocks|DSP Blocks):',s)]
    assert len(resource_lines)==3
    hdmi=next(r for r in setup if r['launch']==r['capture']=='hdmi_tx_slow_clk')
    variants[key]=dict(link_enable=key=='link',nms_enable=True,min_seeds=3,high_default=50,
        setup=setup,hold=hold,min_setup_ns=min(r['slack_ns'] for r in setup),
        min_hold_ns=min(r['slack_ns'] for r in hold),hdmi_setup_ns=hdmi['slack_ns'],
        resources=resource_lines,firmware=firmware,
        top_source_sha256=sha(root/'rtl/ti60f225_oob_top.v'))
    shutil.copy2(root/'rtl/ti60f225_oob_top.v',ROOT/f'reference/e2_variants/ti60f225_oob_top_{key}.v')
shutil.copy2(ROOT/'reports/verification.json',ROOT/'reports/verification_e2.json')

collected=datetime.now(timezone(timedelta(hours=8))).isoformat()
noise_table='\n'.join('| '+r['name']+' | '+' | '.join(str(r['known_background_false_pixels'][v]) for v in ('N24','N50','L50'))+' |'
    for r in noise)
image_table='\n'.join(f'| {r["name"]} | {r["N50"]["edge_pixels"]} / {r["L50"]["edge_pixels"]} | '
    f'{r["N50"]["isolated_pixels"]} / {r["L50"]["isolated_pixels"]} | '
    f'{r["N50"]["components_8"]} / {r["L50"]["components_8"]} | '
    f'{r["N50"]["solid_2x2"]} / {r["L50"]["solid_2x2"]} |'
    for r in images['fixtures'] if not r['name'].startswith('flat_noise_'))
times='\n'.join(f'| E2{"L" if k=="link" else "N"} | {v["hdmi_setup_ns"]:+.3f} | '
    f'{v["min_setup_ns"]:+.3f} | {v["min_hold_ns"]:+.3f} |' for k,v in variants.items())
resources='\n\n'.join(k+':\n'+'\n'.join(v['resources']) for k,v in variants.items())
sample_count=sum(r['samples'] for r in local['units'])
validation=f'''# V10-E2 验证与交付记录

采集时间：{collected}。这是独立实验工程，稳定 C2.1 和 E1 的发布清单校验通过，原目录/固件未覆盖。未自动烧录硬件。

## 修改范围

| 文件 | 变化 |
|---|---|
| rtl/edge/gradient/img_edge_link.sv（新增） | 5×5 方向约束局部图，低候选/高种子，受梯度支持的单像素桥，24级可达性流水，三强种子支持 |
| rtl/edge/video/img_window5x5.sv（新增） | 四行描述符 RAM、水平窗口及边界有效性 |
| rtl/edge/top/img_pipeline.sv | 保留 Sobel/NMS 回退，传递低阈值/方向，等长数据与同步；从已对齐 RGB 精确重算灰度以节省 RAM；M3 显示回退参数 |
| rtl/edge/compose/img_composer.sv | M3 右侧按列对 OR，防止奇数列细线漏采；左 RGB、上一源行行为与一拍延迟不变；参数可回退 |
| rtl/ti60f225_oob_top.v | 板级默认 T=50；新增 E2_LINK_ENABLE、E2_MIN_SEEDS 并传递给核心/HUD |
| rtl/edge/compose/edge_final_hud.sv | E2L/E2N 路径标识 |
| ti60f225_oob.xml | 仅新增两个 design_file，其他设置相同 |
| sim / scripts / reference / docs | 独立局部图参考、实际 RTL 固定图、冻结 E1 核心和原合成器、回退/显示/同步回归，构建收集与说明 |

白平衡、PH2 BGGR、R240/G180/B240、Debayer、Sobel 和方向/NMS 算术、预处理、原按键/阈值上下限、冻结、相机初始化和曝光、DDR、MIPI、HDMI、PLL、关键复位与 SDC 均未修改。顶层归一化新增参数/调用及默认阈值后，与 E1 完全相同。详细补丁见 e2_changes.patch，范围校验见 e2_scope.json。

## 实际验证

- **32 组完整回归通过**，包含色彩/灰度、Sobel 算术、原按键及阈值饱和、所有模式、冻结、FIFO/AXI、异常恢复及连续 DE/HS/VS。
- 冻结原 C2/E1 核心和原 M3 合成器，仅重命名仿真模块；关闭连接且选择原 M3 取样时，补偿延迟后逐像素一致。E2L/E2N 同步一致，M0/M1/M5/M6 内容相同，M3 左彩色图相同；新增边缘不能低于原始幅值 L=25。
- M3 专项覆盖只出现在奇数列的细线、偶数列、随机列样式、奇/偶宽度、WIDTH=1 及 PAIR_EDGE=0 回退。回归的完整数据路径也检查新 M3 列对 OR 规则。M3 显示收益没有计入下面 M2 算法数据。
- **14 组局部图 RTL 与独立参考逐时钟一致**，共 {sample_count} 个时钟采样，覆盖桥开/关、1×1 到 1920 宽和 1080 高、全弱无种子、孤立/两点强响应、缺梯度、错误方向、随机图、边界及连续帧。不发生跨行/跨帧连接。
- 定向模型测试通过：有强支持的短弱缺口恢复；零梯度缺口不凭空填白；单/双点噪声拒绝；超出局部范围的长弱链仍拒绝，明确不是全图追踪。
- **13 张固定输入 × 3 版 = 39 个真实 RTL 输出**，对 N24、N50、L50 的每个像素和 DE/HS/VS 与独立整数/局部图模型核对。均为预处理旁路，输入相同。完整输入、来源和 SHA256 位于 reference/e2_inputs 与 reference/e1_inputs。
- 77 源/28 自定义模块/68 GPIO 的工程端口检查通过，8 项结构检查通过。开源工具对加密 IP 只做公开端口检查；实际 Efinity 综合使用原加密源。

## 降噪与连接的固定图结果

对比图 e2_ab/comparison.png 的四列依次为输入、NMS T=24、NMS T=50、E2L H=50/L=25。两个 T=50 版本使用同一输入、同一 NMS，区别仅在新增连接/小分量规则。

以下是已知无轮廓的平坦灰度背景叠加固定随机高斯噪声，图为 256×192，统计 ROI 去除四周 5 像素（182×246）。其白点都是该合成背景中的误响应：

| 合成噪声输入 | NMS T=24 | NMS T=50 | E2L H50/L25 |
|---|---:|---:|---:|
{noise_table}

在已知三行弱带处，NMS T=50 覆盖 2/3 行，E2L 恢复到 3/3；T=24 也为 3/3。该结论只适用于这个有强边缘支撑的合成短弱带，不能推广为所有真实弱轮廓的召回率。

下面的计数是对真实 RTL 输出的描述，不是通用质量评分。公开人像是真实照片，其余表内图是合成输入，三张运动图仅为固定位置序列：

| 输入 | 白点 N50/L50 | 孤立点 N50/L50 | 8连通分量 N50/L50 | 实心2×2块 N50/L50 |
|---|---:|---:|---:|---:|
{image_table}

文字、人像和短弱带的一些连接改善，同时部分图的实心2×2块增加，说明短桥与弱线保留也可能局部增加线宽。杯纹、低对比 PCB 仍存在较长缺口；默认三强种子会拒绝很小的真实特征。高噪声输入仍有连成簇的误响应。没有人工标注，不报告实拍 Precision/Recall/F1，也不据白点多少宣称全部优化成功。

## 实际编译、时序与资源

Efinity 2026.1.132 下，两版分别实际完成 map/interface/pnr/pgm，均 PASS。编译输入除 E2_LINK_ENABLE 外相同，项目/约束语义相同；最终全部已报告 setup/hold 非负，74.25/148.5 MHz 相关视频时钟双向关系仍被检查，最终 CDC 无同步器警告。

| 版本 | HDMI setup ns | 最小已报告 setup ns | 最小已报告 hold ns |
|---|---:|---:|---:|
{times}

```text
{resources}
```

原工程仍有未使用 JTAG/接口约束等提示，以上仅表示当前约束下的已分析路径通过，不能等同于所有外部 IO 的完整签核或实板稳定性。最终原始报告保存为 e2_link_*、e2_nms_*，总日志为 efinity_v10_e2_*_compile.log。

两版核心统一延迟 5*HTOTAL+60；1080p 下为 11060 周期，比 E1 增加 4433 周期，即 29.85185 微秒。吞吐一像素/时钟，没有新增整帧缓存，不改变相机帧率。相机到屏幕总延迟与长期运行未在实板测量。

## 固件与待上板项目

- 默认实验：programming/ti60f225_oob_V10_E2_Link.bit，普通页 E2L。
- 同条件对照：programming/ti60f225_oob_V10_E2_NMS.bit，普通页 E2N。两版默认 T=50、相同 M3 取样和延迟。
- 原 E1N/E1S 与 C2.1 固件随原稳定目录保留，当前工程中也保留历史副本。
- 仍需实板：同照明机位下真实纸杯花纹、文字、PCB、五官、棋盘、斜线/圆弧与邻近线条，噪点和错接，M3/M4 定位，M5 原样，运动/拖影、冻结恢复、阈值上下限、反复切模式、至少30分钟连续运行、HDMI及U/D/R/L/O。

E2 是局部连接实验，不是完整 Canny；未收到用户上板确认前不替代稳定版。详细步骤见 docs/V10_E2_LINK.md。
'''
(ROOT/'reports/V10_E2_VALIDATION.md').write_text(validation,encoding='utf-8')

report=dict(revision='V10-E2',collected_at=collected,basis='Delivered E1 / confirmed C2.1 color',
    scope=scope,regression_results=tests,local_graph_results=local,image_results=images,
    builds=variants,clock_mhz=148.5,kernel_latency_cycles=11060,added_over_E1_cycles=4433,
    added_over_E1_us=4433/148.5,throughput='one pixel/clock',
    default='NMS, direction-constrained local graph, >=3 high seeds, raw-supported bridge; H50/L25',
    M3='RGB unchanged; pairwise edge OR; independently bypassable',
    hardware_validation='NOT RUN. Stable E1/C2.1 not replaced',
    limits=images['limits'],ground_truth=images['ground_truth'])
files=[ROOT/n for n in sources]
files += [ROOT/n for n in ('README.md','BUILD_NEW_FIRMWARE_REQUIRED.txt','docs/V10_E2_LINK.md','reports/V10_E2_VALIDATION.md')]
files += [f for d in ('ip','ooc','reference/e2_baseline','reference/e2_variants','reference/e1_inputs','reference/e2_inputs',
    'reports/e2_ab','sim/reference') for f in (ROOT/d).rglob('*') if f.is_file() and '__pycache__' not in f.parts]
files += list((ROOT/'sim').glob('tb*.sv'))
files += [ROOT/f'scripts/{n}.py' for n in ('check_e2_scope','finalize_e2','package_e2','prepare_e2_nms_build',
    'verify_e2','verify_e2_images','e2_model','verify_e1','run_tests','check_project','project_structure','test_project_structure')]
files += [ROOT/f'reports/{n}' for n in ('verification_e2.json','e2_local_verification.json','e2_image_verification.json',
    'e2_scope.json','e2_changes.patch','project_checks.json','project_structure_regression.json','board_interface_compile.log',
    'rtl_regression_v10_e2.log','e2_local.log','e2_images.log','e2_project_checks.log',
    'e2_image_N24.log','e2_image_N50.log','e2_image_L50.log')]
for key,v in variants.items():
    files += [ROOT/f['path'] for f in v['firmware'].values()]
    files += [ROOT/f'reports/e2_{key}_{s}' for s in ('timing.rpt','cdc.rpt','resources.rpt','synthesis.log','place_route.log','bitstream.log')]
    files.append(ROOT/f'reports/efinity_v10_e2_{key}_compile.log')
report['sha256']={f.relative_to(ROOT).as_posix():sha(f) for f in dict.fromkeys(files)}
(ROOT/'reports/v10_e2_release_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('V10-E2 FINAL PASS: 32 regressions, 14 local grids, 39 actual RTL images; two actual builds; stable E1/C2 preserved')
for k,v in variants.items():print(k,'HDMI setup',v['hdmi_setup_ns'],'min hold',v['min_hold_ns'],v['resources'])
