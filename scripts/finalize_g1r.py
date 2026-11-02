"""Publish only firmware whose actual build and RTL evidence match current source."""
from pathlib import Path
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from record_g1r_inputs import snapshot

ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'reports'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def timing(p):
    text=p.read_text()
    summary=text.split('Setup (Max) Clock Relationship',1)[1].split('NOTE: Values',1)[0]
    setup,hold=summary.split('Hold (Min) Clock Relationship',1)
    def rows(s):
        return [dict(launch=m[0],capture=m[1],constraint=float(m[2]),slack=float(m[3]))
                for m in re.findall(r'^\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(R-R\)',s,re.M)]
    a,b=rows(setup),rows(hold)
    assert a and b and min(r['slack'] for r in a+b)>=0,'Final setup/hold failed'
    for x,y in [('vid_clk_dvi2','hdmi_tx_slow_clk'),('hdmi_tx_slow_clk','vid_clk_dvi2')]:
        assert any(r['launch']==x and r['capture']==y for r in a),'Video clock relation omitted'
    return dict(min_setup_ns=min(r['slack'] for r in a),min_hold_ns=min(r['slack'] for r in b),
                hdmi_setup_ns=next(r['slack'] for r in a if r['launch']==r['capture']=='hdmi_tx_slow_clk'))

def main():
    current=snapshot()
    assert current==json.loads((REPORTS/'g1r_build_inputs.json').read_text()),'Build input differs'
    build=(REPORTS/'efinity_g1r_compile.log').read_text(encoding='utf8')
    for stage in ['map','interface','pnr','pgm']:
        assert re.search(r'\b'+stage+r'\s*:\s*PASS',build),stage
    assert 'G1R build source snapshot MATCH' in build,'Incomplete or stale compile'
    integrated=json.loads((REPORTS/'g1r_integration_manifest.json').read_text())
    assert integrated['status']=='PASS' and integrated['inputs']==current
    cases_root=ROOT/'sim/g1r_data'
    cases=json.loads((cases_root/'work/verification_summary.json').read_text())
    assert cases['status']=='PASS' and not cases['board_tested']
    assert cases['final_source_sha256']==sha(ROOT/'rtl/edge/geometry/img_geometry.sv')
    assert cases['bench_sha256']==sha(ROOT/'sim/tb_g1r_raster.sv')
    for row in cases['tests']:
        directory=Path(row['params']['DATA_DIR'].strip('"'))
        assert row['manifest_sha256']==sha(directory/'manifest.json'),row['suite']
    preserved=json.loads((REPORTS/'preserved_projects.json').read_text())
    for project,files in preserved.items():
        origin=ROOT.parents[1]/project/'ti60f225_oob'
        for path,expected in files.items():assert sha(origin/path)==expected,('Original changed',project,path)
    old=ROOT.parents[1]/'V11_G1/ti60f225_oob'
    old_manifest=json.loads((old/'reports/g1_release_manifest.json').read_text())
    changed=[n for n,h in old_manifest['source_sha256'].items() if sha(ROOT/n)!=h]
    assert set(changed)=={'rtl/edge/top/img_pipeline.sv','rtl/edge/geometry/img_geometry.sv','rtl/edge/geometry/img_geometry_overlay.sv'}
    for n in ['ti60f225_oob.sdc','ti60f225_oob.peri.xml']:
        assert sha(ROOT/n)==sha(old/n),'Protected constraints/interface changed'
    t=timing(ROOT/'outflow/ti60f225_oob.timing.rpt')
    cdc=(ROOT/'outflow/ti60f225_oob.cdc.rpt').read_text()
    assert 'No Synchronizer warnings to report.' in cdc
    warning_history=(ROOT/'outflow/ti60f225_oob.warn.log').read_text()
    # Efinity appends warn/err across invocations, unlike the final map/STA.
    # Keep history, but judge this build's last synthesis section only.
    assert 'Efinity Synthesis Started' in warning_history
    warnings='Efinity Synthesis Started'+warning_history.rsplit('Efinity Synthesis Started',1)[1]
    assert not re.search(r'Mapping into logic memory block.*g_geometry',warnings),'Geometry RAM inference failed'
    place=(ROOT/'outflow/ti60f225_oob.place.rpt').read_text()
    resources={}
    for label in ['XLRs','Memory Blocks','DSP Blocks']:
        m=re.search(r'^'+label+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
        resources[label]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
        assert int(m[1])<=int(m[2])
    for suffix in ['timing.rpt','place.rpt','hier_util.rpt','map.rpt','cdc.rpt','warn.log','err.log','log']:
        shutil.copy2(ROOT/f'outflow/ti60f225_oob.{suffix}',REPORTS/f'g1r_{suffix}')
    (REPORTS/'g1r_warn_history.log').write_text(warning_history,encoding='utf8')
    (REPORTS/'g1r_warn.log').write_text(warnings,encoding='utf8')
    artifacts=[]
    for suffix in ['bit','hex']:
        src=ROOT/f'outflow/ti60f225_oob.{suffix}'
        dst=ROOT/f'programming/ti60f225_oob_V11_G1R.{suffix}'
        assert src.stat().st_size>0
        assert not dst.exists() or sha(src)==sha(dst),'Refuse different released firmware overwrite'
        shutil.copy2(src,dst)
        artifacts.append(dict(path=dst.relative_to(ROOT).as_posix(),bytes=dst.stat().st_size,sha256=sha(dst)))
    frames={}
    for row in cases['tests']:
        p=cases_root/'work'/row['suite']/'tb_g1r_raster_run.log'
        m=re.search(r'(?:G1R RASTER PASS.*frames=|G1R REFERENCE DONE frames=)(\d+)',p.read_text())
        assert m,row['suite'];frames[row['suite']]=int(m[1])
    record=dict(status='OFFLINE_AND_BUILD_PASS_AWAITING_BOARD',revision='V11-G1R',marker='M7 G1R',
                board_tested=False,baseline_and_G1_preserved=True,changed_from_G1=changed,
                inputs=current,resources=resources,timing=t,geometry_frames=frames,
                hd_max_processing_cycles=cases.get('hd_max_processing_cycles'),
                integration=integrated['tests'],artifacts=artifacts)
    (REPORTS/'g1r_release_manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
    rows=['# V11-G1R 实际验证记录','',
          '状态：最终源码的 RTL 仿真、Efinity 编译与报告时序通过；尚未上板验收。',
          '本轮没有真实摄像头帧回放，不能将合成用例通过率当作真实场景准确率。','',
          '## 改动','',
          '相对失败反馈对应的 G1，只改 img_geometry.sv、img_geometry_overlay.sv、img_pipeline.sv 三项 RTL。',
          '以有界候选轮廓搜索替代全 ROI 单框；矩形四边/缺口/角点/内部密度验证；保留圆形检查，增加小目标拒绝与更严格圆周覆盖；M7 显示绿色支持、琥珀补线及 NONE 原因。',
          'M0～M6、DDR/MIPI/相机初始化/PLL/编码器/复位和关键约束保持。识别独立旁路，不向原视频施加背压。原 G1 与灰度基准的源码、约束及原 bit 已逐项校验。','',
          '## 离线证据','', '| 测试组 | 实际帧数 | 结果 |','|---|---:|---|']
    for label,n in frames.items():rows.append(f'| {label} | {n} | '+('复现旧 G1 孤立噪点/短缺口拒绝' if label=='baseline' else 'PASS')+' |')
    rows+=['',
           '额外通过 7 帧实际 RGB→PRE2→Sobel→NMS→连接→识别集成；绿色/琥珀虚线/NONE 无虚框/字符对齐的叠加测试；7 组原视频/控制/HUD/异常恢复回归；关闭识别支路的旧 M7 回退；83 源公共接口检查与 8 个工程元数据反例。',
           'full-HD 几何组为真实 1920×1080、2200×1125 栅格，包含正常图形、孤立噪点、缺口、NONE、队列溢出和下一帧恢复。',
           f'HD 测到的最大预提交处理周期：{cases.get("hd_max_processing_cycles")}；内部截止预算 400000 拍。它不是对所有输入都完成分类的保证；超出预算时明确 NONE/TIMEOUT。',
           '结果、框、四边掩码、诊断只在 VS 更新；有上一帧滞后，移动用例检查对应上一帧的框与空白清除。','',
           '## Efinity 最终报告','', '| 资源 | 灰度基准 | 原 G1 | G1R |','|---|---:|---:|---:|']
    base=json.loads((ROOT.parents[1]/'v11-gray-baseline/ti60f225_oob/reports/baseline_release_manifest.json').read_text())
    for name,r in resources.items():
        rows.append(f'| {name} | {base["resources"][name]["used"]} | {old_manifest["resources"][name]["used"]} | {r["used"]}/{r["available"]} ({r["percent"]}) |')
    rows+=['',f'最小 setup +{t["min_setup_ns"]:.3f} ns，最小 hold +{t["min_hold_ns"]:.3f} ns；HDMI 像素域 setup +{t["hdmi_setup_ns"]:.3f} ns。',
           'map/interface/pnr/pgm 全部 PASS；CDC 无 synchronizer 警告。SDC 未删改；原有未使用接口与外部引脚提示仍存在。这些报告不能替代外部 IO 或长期实板稳定性检查。','',
           '## 使用边界','',
           '中央 ROI 单目标，矩形大致与图像坐标轴平行。最大候选可能是背景；相邻边缘可能误合并，大小接近的分离目标会被拒绝。圈至少 12×12 汇聚格，矩形至少 8×8。坐标量化约 8 像素，W/H 及诊断为 HEX，不是毫米。',
           '补线只显示有足够四边支持的局部缺口，不写回原边缘，也不能推断完全缺失的一条边。无真实帧回放和上板反馈，不声称普遍识别成功。','',
           '早期失败构建/旧源码测试保留于 attempt* 报告或 sim/g1r_data/work/archive，均不作为最终通过证据。最终清单逐项绑定当前源码和最终固件。']
    (REPORTS/'V11_G1R_VALIDATION.md').write_text('\n'.join(rows)+'\n',encoding='utf8')
    start=['# V11-G1R 使用入口','',
           '单目标轮廓识别与局部矩形补全实验版。已通过本次离线测试与 Efinity 编译，尚未上板验收。','',
           '工程：`'+str(ROOT)+'`','',
           '固件：`programming/ti60f225_oob_V11_G1R.bit`。切到 M7，确认识别页第一行出现 G1R。','',
           '绿色表示有支持的模型/边缘，琥珀色虚线表示推断缺口。NONE 时不画目标框，旁边显示 NOEDGE/SIZE/GAP/MULTI 等原因。',
           '先用一个较大、正对镜头的黑白目标，完整放在灰色角标内。可先用 PRE2、T=50，或沿用你的稳定参数。','',
           '使用与限制：[docs/V11_G1R.md](docs/V11_G1R.md)。实板测试卡：[test_cards](test_cards/README.md)。',
           '实际验证与资源：[reports/V11_G1R_VALIDATION.md](reports/V11_G1R_VALIDATION.md)。源码/固件哈希：[reports/g1r_release_manifest.json](reports/g1r_release_manifest.json)。','',
           '原 v11-gray-baseline 和 V11_G1 保持独立。本轮无需压缩工程，直接使用上述路径。']
    (ROOT/'START_HERE_G1R.md').write_text('\n'.join(start)+'\n',encoding='utf8')
    print('G1R RELEASE PASS: source, evidence, original preservation, final timing and firmware agree')
    print(json.dumps(dict(resources=resources,timing=t,frames=frames,artifacts=artifacts),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
