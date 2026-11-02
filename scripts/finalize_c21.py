"""Publish C2.1 only after actual regression, interface and Efinity checks."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib, json, re, shutil, xml.etree.ElementTree as ET
from check_c21_scope import check

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outflow'
scope=check()
tests=json.loads((ROOT/'reports/verification.json').read_text())
assert len(tests)==30 and all(t['status']=='PASS' for t in tests),'C2.1 regression incomplete'
assert 'ALL REGRESSIONS PASSED' in (ROOT/'reports/rtl_regression_v10_c21.log').read_text(encoding='utf-8-sig')
for top,label in (
    ('tb_control_white_balance','CONTROL WB C2.1 PASS'),('tb_final_hud','V10-C2.1 HUD PASS'),
    ('tb_bayer_phase','BAYER PHASE PASS 1101 fields, 66000 interior pixel pairs'),
    ('tb_color_precision','COLOR PRECISION PASS 262144 samples'),('tb_mode_threshold_sync','MODE/THRESHOLD PASS')):
    assert label in (ROOT/f'sim/build/{top}_run.log').read_text(),top
project=json.loads((ROOT/'reports/project_checks.json').read_text())
assert project['public_interface_elaboration']=='PASS' and project['source_files']==74
structure=json.loads((ROOT/'reports/project_structure_regression.json').read_text())
assert len(structure)==8 and all(t['status']=='PASS' for t in structure)
flow=(ROOT/'reports/efinity_v10_c21_compile.log').read_text(encoding='utf-8-sig')
for stage in ('map','interface','pnr','pgm'):
    assert re.search(r'\b'+stage+r'\s*:\s*PASS',flow),stage
timing=(OUT/'ti60f225_oob.timing.rpt').read_text()
def rows(s):
    return [dict(launch=m[0],capture=m[1],constraint_ns=float(m[2]),slack_ns=float(m[3]))
        for m in re.findall(r'^\s*(\S+)\s+(\S+)\s+([\d.-]+)\s+([\d.-]+)\s+\(R-R\)',s,re.M)]
setup=rows(timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min)',1)[0])
hold=rows(timing.split('Hold (Min) Clock Relationship',1)[1].split('NOTE:',1)[0])
assert setup and hold and min(p['slack_ns'] for p in setup+hold)>=0,'Final timing failure'
for launch,capture in (('vid_clk_dvi2','hdmi_tx_slow_clk'),('hdmi_tx_slow_clk','vid_clk_dvi2')):
    assert any(p['launch']==launch and p['capture']==capture for p in setup),'Related phase/video path cut'
assert 'No Synchronizer warnings to report.' in (OUT/'ti60f225_oob.cdc.rpt').read_text()
place=(OUT/'ti60f225_oob.place.out').read_text(errors='replace')
assert not re.search(r'No pins matched[^\n]*(video_health|edge_read_error_sync)',place)
compiled=[ROOT/e.attrib['name'] for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter() if e.tag.rsplit('}',1)[-1]=='design_file']
compiled += [ROOT/n for n in ('ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem')]
latest=max(f.stat().st_mtime for f in compiled if f.suffix in ('.v','.sv','.vh','.sdc'))
for name in ('verification.json','project_checks.json'):
    assert (ROOT/'reports'/name).stat().st_mtime>=latest,'Stale '+name
files=list(compiled)
for ext in ('bit','hex'):
    src=OUT/f'ti60f225_oob.{ext}';assert src.stat().st_size>100000
    assert all(f.stat().st_mtime<=src.stat().st_mtime+(2 if f.name=='ti60f225_oob.xml' else 0) for f in compiled),'Stale bitstream'
    dest=ROOT/f'programming/ti60f225_oob_V10_C2_1.{ext}'
    if dest.exists():assert dest.read_bytes()==src.read_bytes(),'Preserve existing release'
    else:shutil.copy2(src,dest)
    files.append(dest)
for suffix,name in (('timing.rpt','timing.rpt'),('cdc.rpt','cdc.rpt'),('place.rpt','resources.rpt'),
    ('map.out','synthesis.log'),('place.out','place_route.log'),('pgm.out','bitstream.log')):
    shutil.copy2(OUT/f'ti60f225_oob.{suffix}',ROOT/f'reports/c21_{name}')
shutil.copy2(ROOT/'reports/verification.json',ROOT/'reports/verification_c21.json')
hdmi=next(p for p in setup if p['launch']==p['capture']=='hdmi_tx_slow_clk')
sm=min(p['slack_ns'] for p in setup);hm=min(p['slack_ns'] for p in hold)
report=dict(revision='V10-C2.1',collected_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
    tool='Efinity 2026.1.132 / Ti60F225 / I3 / seed 1',scope=scope,regression_results=tests,
    setup=setup,hold=hold,min_setup_slack_ns=sm,min_hold_slack_ns=hm,hdmi_setup_slack_ns=hdmi['slack_ns'],
    wb_default_q8=[0x240,0x180,0x240],wb_gain=[2.25,1.5,2.25],default_bayer_phase=2,bayer_pattern='BGGR',
    board_basis='User confirmed C2 PH2, and GAIN 240/180/240 in hardware photo',
    board_validation='C2.1 startup preset and long-term hardware operation not yet tested; white/gray card calibration pending',
    algorithm_and_video_latency='UNCHANGED from C2',wb_step_q8=8,
    inherited_warnings='Unused JTAG/IO constraints and HUD static-function preservation notice remain; no CDC warnings')
resources=(OUT/'ti60f225_oob.place.rpt').read_text()
resource_lines='\n'.join(s for s in resources.splitlines() if re.match(r'^(XLRs|Memory Blocks|DSP Blocks):',s))
table='\n'.join(f'| {p["launch"]} → {p["capture"]} | {p["slack_ns"]:+.3f} |' for p in setup)
validation=f'''# V10-C2.1 验证记录

采集时间：{report['collected_at']}。在现有 V10 工程直接修改，未创建新项目。

相对已发布 C2，只改变控制器的四个复位默认值及 HUD 版本标识。上电 PH2（BGGR），R/G/B 增益为 0x240/0x180/0x240（2.25/1.5/2.25 倍）。去除这四个常量变化后，控制器行为与 C2 相同；HUD 计数、字体、色块及输出寄存器时序相同。其他 72 个工程源文件、外设、SDC 和 Gamma 数据均与 C2 发布清单一致。

## 已执行

- 30 组完整 RTL 回归全部通过，见 `verification_c21.json` 和 `rtl_regression_v10_c21.log`。
- 新默认 PH/增益、R/B 在 MAX 继续加不回绕、减至 238 再增回 240、G 增减和上下限、相位切换、冻结、阈值独立及复位恢复均通过。
- C2.1 版本标识、完整四档名称及 RGB/白/黑参考色块通过；四种 Bayer 1101 场/66000 内部双像素结果、262144 组像素×增益精度及连续同步回归通过。
- 74 个工程源的模块接口检查、8 项工程结构检查通过。加密 IP 在开源检查中仅用公开接口占位；Efinity 编译使用实际加密源。
- Efinity map/interface/pnr/pgm 全部 PASS，已生成独立 C2.1 bit/hex，源文件时效检查通过。旧 C2/C1/V10 固件及清单保持。

## 最终时序

已报告时钟关系的 setup/hold 均非负：最小 setup **{sm:+.3f} ns**，最小 hold **{hm:+.3f} ns**；HDMI 148.5 MHz setup **{hdmi['slack_ns']:+.3f} ns**。148.5 ↔ 74.25 MHz 两向路径继续检查，SDC 没有修改。CDC 报告没有同步器警告。原有 JTAG/未使用接口约束及 HUD 函数变量保持提示仍在；不据此宣称所有 IO 已完整签核。

| 时钟关系 | setup 余量 ns |
|---|---:|
{table}

```text
{resource_lines}
```

实际时序、CDC、资源和编译各阶段报告见 `c21_*`；编译总日志 `efinity_v10_c21_compile.log`。

## 实板依据与仍需复核

用户已在 C2 实板确认 PH2，并提供 GAIN 240/180/240。照片中的每通道 CLIP=00F，为 15/256（约 5.9%）的抽样点裁剪；场景正对灯具，不是白/灰卡标定。本版保存这组用户预设，没有新增曝光、自动白平衡、色彩矩阵或边缘算法。照片及数字记录在 `reference/c21_board_feedback`。

C2.1 上电默认值、断电/KEY0 复位后恢复、调增益时的显示稳定性及均匀白/灰卡效果仍需用户上板复核，不能用编译/仿真替代。操作见 `docs/V10_C21_PRESET.md`。色彩复核后再继续边缘质量优化。

烧录 `programming/ti60f225_oob_V10_C2_1.bit`，显示 C2.1、PH:2 BGGR、GAIN 240/180/240。完整源码包为 `version/packages/ti60f225_oob_V10_C2_1_preset.zip`；回退可用原 C2 固件或完整包。校验值见本版发布清单。
'''
(ROOT/'reports/V10_C21_VALIDATION.md').write_text(validation,encoding='utf-8')
files += [ROOT/n for n in ('README.md','docs/V10_C21_PRESET.md','reports/V10_C21_VALIDATION.md')]
files += list((ROOT/'sim').glob('tb*.sv'))
files += [ROOT/f'scripts/{n}.py' for n in ('check_c21_scope','finalize_c21','package_c21','run_tests','check_project','project_structure','test_project_structure')]
files += [f for d in ('reference/c21_baseline','reference/c21_board_feedback') for f in (ROOT/d).rglob('*') if f.is_file()]
files += [ROOT/f'programming/ti60f225_oob_{v}.{e}' for v in ('V10','V10_C1','V10_C2') for e in ('bit','hex')]
report['sha256']={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in dict.fromkeys(files)}
(ROOT/'reports/v10_c21_release_manifest.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'C2.1 FINAL PASS: {len(tests)} groups; min setup {sm:+.3f} ns; hold {hm:+.3f} ns; HDMI setup {hdmi["slack_ns"]:+.3f} ns')
for ext in ('bit','hex'):
    f=ROOT/f'programming/ti60f225_oob_V10_C2_1.{ext}';print(f.name,hashlib.sha256(f.read_bytes()).hexdigest())
