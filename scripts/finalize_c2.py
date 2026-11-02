"""Collect C2 only after real regression and Efinity final timing pass."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib, json, re, shutil, xml.etree.ElementTree as ET
from check_c2_scope import check

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outflow'
scope=check()
tests=json.loads((ROOT/'reports/verification.json').read_text())
assert len(tests)==30 and all(t['status']=='PASS' for t in tests),'Incomplete C2 regression'
assert any(t['test']=='tb_bayer_phase' for t in tests)
assert 'ALL REGRESSIONS PASSED' in (ROOT/'reports/rtl_regression_v10_c2.log').read_text(encoding='utf-8-sig')
for top,label in (
    ('tb_debayer_color','DEBAYER COLOR PASS 267 fields'),
    ('tb_bayer_phase','BAYER PHASE PASS 1101 fields, 66000 interior pixel pairs'),
    ('tb_control_white_balance','CONTROL WB C2 PASS'),
    ('tb_color_precision','COLOR PRECISION PASS 262144 samples'),
    ('tb_color_pipeline','COLOR PIPELINE PASS'),('tb_final_hud','V10-C2 HUD PASS')):
    assert label in (ROOT/f'sim/build/{top}_run.log').read_text(),top
project=json.loads((ROOT/'reports/project_checks.json').read_text())
assert project['public_interface_elaboration']=='PASS' and project['source_files']==74
structure=json.loads((ROOT/'reports/project_structure_regression.json').read_text())
assert len(structure)==8 and all(t['status']=='PASS' for t in structure)
flow=(ROOT/'reports/efinity_v10_c2_compile.log').read_text(encoding='utf-8-sig')
for stage in ('map','interface','pnr','pgm'):
    assert re.search(r'\b'+stage+r'\s*:\s*PASS',flow),'Efinity stage incomplete: '+stage

timing=(OUT/'ti60f225_oob.timing.rpt').read_text()
def rows(s):
    return [dict(launch=m[0],capture=m[1],constraint_ns=float(m[2]),slack_ns=float(m[3]))
            for m in re.findall(r'^\s*(\S+)\s+(\S+)\s+([\d.-]+)\s+([\d.-]+)\s+\(R-R\)',s,re.M)]
setup=rows(timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min)',1)[0])
hold=rows(timing.split('Hold (Min) Clock Relationship',1)[1].split('NOTE:',1)[0])
assert setup and hold and min(p['slack_ns'] for p in setup+hold)>=0,'Negative final timing'
for launch,capture in (('vid_clk_dvi2','hdmi_tx_slow_clk'),('hdmi_tx_slow_clk','vid_clk_dvi2')):
    assert any(p['launch']==launch and p['capture']==capture for p in setup),'Related video/phase path cut'
assert 'No Synchronizer warnings to report.' in (OUT/'ti60f225_oob.cdc.rpt').read_text()
place=(OUT/'ti60f225_oob.place.out').read_text(errors='replace')
assert not re.search(r'No pins matched[^\n]*(video_health|edge_read_error_sync)',place),'CDC constraints not matched'
resources=(OUT/'ti60f225_oob.place.rpt').read_text()

files=[ROOT/e.attrib['name'] for e in ET.parse(ROOT/'ti60f225_oob.xml').getroot().iter()
       if e.tag.rsplit('}',1)[-1]=='design_file']
files += [ROOT/p for p in ('ti60f225_oob.xml','ti60f225_oob.peri.xml','ti60f225_oob.sdc','rtl/gamma_conrrection/2P2.mem')]
compiled=tuple(files)
latest_rtl=max(f.stat().st_mtime for f in compiled if f.suffix in ('.v','.sv','.vh','.sdc'))
assert (ROOT/'reports/verification.json').stat().st_mtime>=latest_rtl,'Regression is stale'
for ext in ('bit','hex'):
    src=OUT/f'ti60f225_oob.{ext}';assert src.stat().st_size>100000
    assert all(f.stat().st_mtime<=src.stat().st_mtime+(2 if f.name=='ti60f225_oob.xml' else 0) for f in compiled),'Build is stale'
    dest=ROOT/f'programming/ti60f225_oob_V10_C2.{ext}'
    if dest.exists():assert dest.read_bytes()==src.read_bytes(),'Existing C2 firmware differs; preserve it'
    else:shutil.copy2(src,dest)
    files.append(dest)
for suffix,name in (('timing.rpt','timing.rpt'),('cdc.rpt','cdc.rpt'),('place.rpt','resources.rpt'),
                    ('map.out','synthesis.log'),('place.out','place_route.log'),('pgm.out','bitstream.log')):
    shutil.copy2(OUT/f'ti60f225_oob.{suffix}',ROOT/f'reports/c2_{name}')
shutil.copy2(ROOT/'reports/verification.json',ROOT/'reports/verification_c2.json')
setup_min=min(p['slack_ns'] for p in setup);hold_min=min(p['slack_ns'] for p in hold)
hdmi=next(p for p in setup if p['launch']==p['capture']=='hdmi_tx_slow_clk')
report=dict(revision='V10-C2',collected_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
            tool='Efinity 2026.1.132 / Ti60F225 / I3 / seed 1',scope=scope,
            regression_results=tests,setup=setup,hold=hold,min_setup_slack_ns=setup_min,
            min_hold_slack_ns=hold_min,hdmi_setup_slack_ns=hdmi['slack_ns'],
            debayer_regression='1101 fields, 66000 interior pixel pairs, four Bayer phases; original GRBG 267 fields also pass',
            video_latency='UNCHANGED, Debayer sync 5 clocks, RGB balance 1 clock',
            raw_gain='UNITY 0x0100',wb_default_q8=[256,256,256],wb_step_q8=8,
            bayer_phases=['GRBG','RGGB','BGGR','GBRG'],default_bayer_phase=1,
            board_validation='NOT RUN for C2; actual sensor phase and color calibration still require user test',
            prior_board_feedback='C1 stable with normal texture but red/green/blue reproduction incorrect',
            existing_warnings='Inherited unused JTAG/IO constraints remain; all defined final clock setup/hold rows checked')
table='\n'.join(f'| {p["launch"]} → {p["capture"]} | {p["constraint_ns"]:.3f} | {p["slack_ns"]:+.3f} |' for p in setup)
resource_lines='\n'.join(line for line in resources.splitlines() if re.match(r'^(XLRs|Memory Blocks|DSP Blocks|DSPs):',line))
validation=f'''# V10-C2 验证记录

采集时间：{report['collected_at']}。本版仍为第一步色彩修正，直接修改原 V10 工程。实板 C2 测试尚未执行。

## 修改范围

相对已交付 C1，仅五个色彩 RTL 文件发生变化：Debayer 算术选择、Debayer 封装端口、控制器、最终 HUD、顶层色彩控制连线。基于 C1 SHA256 清单及备份逐文件比较通过；顶层去除新增相位线后完全一致。行缓存、窗口计数、同步、输出时序、工程设置、DDR/MIPI/HDMI/PLL/复位/曝光，以及灰度、预处理、Sobel、合成都未修改。

## 实际执行的检查

- 30 组完整回归通过，详见 `rtl_regression_v10_c2.log` 和 `verification_c2.json`。
- 四种 Bayer：1101 个测试场、66000 个有效内部双像素结果，纯 RGB、256 级中性灰、彩条、棋盘格、二维渐变、帧中调节保持和全部相位切换均与独立双线性参考一致。该测试中的图案是合成输入。
- 原 GRBG 回归仍通过：267 个场、16020 个内部双像素结果。说明增加其余排列没有破坏 C1 已验证的 GRBG 数字结果；不证明真实模组属于 GRBG。
- 262144 组像素/增益穷举覆盖全部 8 位像素乘 10 位增益，舍入、饱和、裁剪标志与每帧锁存通过。
- 中性默认增益、R/G/B/P 选择、相位加减及回绕、原冻结与阈值行为通过。HUD 五个参考色块的像素值通过。
- 74 个工程源文件的接口检查、8 个工程结构检查通过。接口检查对加密 IP 使用接口占位，不是其功能仿真；Efinity 对实际加密 IP 完成综合。
- Efinity map/interface/pnr/pgm 均 PASS，实际生成 C2 `.bit/.hex`。SDC 和外设文件未改，148.5 ↔ 74.25 MHz 两向相关时钟路径均保持分析；未新增时钟组豁免。

## 最终时序与资源

全部已报告时钟关系 setup/hold 均非负，最小 setup **{setup_min:+.3f} ns**、最小 hold **{hold_min:+.3f} ns**；HDMI 148.5 MHz setup **{hdmi['slack_ns']:+.3f} ns**。CDC 报告为 `No Synchronizer warnings to report.`。原有未使用 JTAG/接口约束提示仍在，不能据此声称所有 IO 均已完整签核。

| 发起 → 接收时钟 | 约束 ns | setup 余量 ns |
|---|---:|---:|
{table}

```text
{resource_lines}
```

完整时序、CDC、资源、综合、布局布线和烧录生成日志保存在 `c2_*` 文件中；编译总日志为 `efinity_v10_c2_compile.log`。

## 上板仍需确认

实际摄像头 Bayer 相位尚未确定；默认 PH:1 RGGB 是试验起点。必须先检查 M6 固定红/绿/蓝/白/黑色块，再用真实 RGB 物体选择 PH，最后以白/灰卡调增益。操作见 `docs/V10_C2_COLOR.md`。本次不宣称已完成颜色标定，也不将合成图案仿真作为实拍效果。

用户对 C1 的稳定性反馈已记录。C2 的长期运行、动态切 PH、运动/冻结、肤色和彩色花纹仍需实板复核。边缘算法优化等待色彩结果确认后再进行。

## 交付与回退

烧录 `programming/ti60f225_oob_V10_C2.bit`，核对 M6 第一行 `C2 RAW`、第四行 `C2 RAW1X CLIP` 及 PH。源码和烧录文件的校验值见 `v10_c2_release_manifest.json`，完整包另有 SHA256 侧文件。原 C1/V10 烧录文件、清单和 C1 完整包保留；五个修改前的色彩 RTL 文件在 `reference/c2_baseline/rtl`。
'''
(ROOT/'reports/V10_C2_VALIDATION.md').write_text(validation,encoding='utf-8')
files += [ROOT/'README.md',ROOT/'docs/V10_C2_COLOR.md',ROOT/'reports/V10_C2_VALIDATION.md']
files += list((ROOT/'sim').glob('tb*.sv'))
files += [ROOT/f'scripts/{name}.py' for name in ('check_c2_scope','finalize_c2','package_c2','run_tests','check_project','project_structure','test_project_structure')]
files += list(BASE for BASE in (ROOT/'reference/c2_baseline').rglob('*') if BASE.is_file())
report['sha256']={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in dict.fromkeys(files)}
(ROOT/'reports/v10_c2_release_manifest.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'V10-C2 FINAL PASS: {len(tests)} regression groups; setup {setup_min:+.3f} ns; hold {hold_min:+.3f} ns')
for ext in ('bit','hex'):
    f=ROOT/f'programming/ti60f225_oob_V10_C2.{ext}';print(f.name,hashlib.sha256(f.read_bytes()).hexdigest())
