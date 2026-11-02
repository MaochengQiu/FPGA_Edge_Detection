from pathlib import Path
import json,hashlib,re,shutil
from record_g1r_inputs import snapshot
from finalize_g1r import timing
R=Path(__file__).resolve().parents[1];P=R/'reports'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 now=snapshot();assert now==json.loads((P/'g1r_build_inputs.json').read_text())
 log=(P/'efinity_g2_compile.log').read_text();assert 'snapshot MATCH' in log
 for s in ['map','interface','pnr','pgm']:assert re.search(r'\b'+s+r'\s*:\s*PASS',log),s
 integ=json.loads((P/'g1r_integration_manifest.json').read_text());assert integ['status']=='PASS' and integ['inputs']==now
 for w in [512,1920]:
  t=json.loads((P/f'g2_shapes_{w}.json').read_text());assert t['status']=='PASS'
  for n,h in t['source'].items():assert sha(R/n)==h
 neg=json.loads((P/'g2_negatives.json').read_text());assert neg['status']=='PASS' and neg['source_sha256']==sha(R/'rtl/edge/geometry/img_geometry.sv')
 for suite in ['startup','reset','deadline','timeout']:
  t=json.loads((R/f'sim/g1r_data/work/results_{suite}.json').read_text());assert t['status']=='PASS' and t['source_sha256']==sha(R/'rtl/edge/geometry/img_geometry.sv')
 old=R.parents[1]/'V11_G1R/ti60f225_oob';om=json.loads((old/'reports/g1r_release_manifest.json').read_text())
 changed=[]
 for n,h in om['inputs']['source_sha256'].items():
  assert sha(old/n)==h,('original changed',n)
  if sha(R/n)!=h:changed.append(n)
 assert set(changed)=={'rtl/edge/geometry/img_geometry.sv','rtl/edge/geometry/img_geometry_overlay.sv','rtl/edge/top/img_pipeline.sv'}
 for a in om['artifacts']:assert sha(old/a['path'])==a['sha256']
 base=R.parents[1]/'v11-gray-baseline/ti60f225_oob';bm=json.loads((base/'reports/baseline_release_manifest.json').read_text())
 for n,h in bm['source_sha256'].items():assert sha(base/n)==h
 for a in bm['artifacts']:
  f=Path(a['path']);f=f if f.is_absolute() else base/f;assert sha(f)==a['sha256']
 tt=timing(R/'outflow/ti60f225_oob.timing.rpt')
 assert 'No Synchronizer warnings to report.' in (R/'outflow/ti60f225_oob.cdc.rpt').read_text()
 resources={};place=(R/'outflow/ti60f225_oob.place.rpt').read_text()
 for k in ['XLRs','Memory Blocks','DSP Blocks']:
  m=re.search(r'^'+k+r':\s*(\d+) / (\d+) \(([^)]+)\)',place,re.M);assert m
  resources[k]={'used':int(m[1]),'total':int(m[2]),'percent':m[3]}
 for ext in ['timing.rpt','place.rpt','hier_util.rpt','map.rpt','cdc.rpt','warn.log','log']:shutil.copy2(R/f'outflow/ti60f225_oob.{ext}',P/f'g2_{ext}')
 artifacts=[]
 for ext in ['bit','hex']:
  src=R/f'outflow/ti60f225_oob.{ext}';dst=R/f'programming/ti60f225_oob_V11_G2.{ext}'
  assert not dst.exists() or sha(dst)==sha(src)
  shutil.copy2(src,dst);artifacts.append(dict(path=dst.relative_to(R).as_posix(),sha256=sha(dst),bytes=dst.stat().st_size))
 record=dict(revision='V11-G2',status='OFFLINE_AND_BUILD_PASS_AWAITING_BOARD',board_tested=False,inputs=now,resources=resources,timing=tt,artifacts=artifacts,changed=changed,originals_preserved=True)
 (P/'g2_release_manifest.json').write_text(json.dumps(record,indent=2))
 lines=['# V11-G2 实际验证与交付记录','','状态：离线测试、最终 Efinity 编译及报告时序通过；没有实板验收结论。','','## 功能与范围','','新增 ELLIPSE，M7 给真实圆/椭圆轮廓着色，中心十字仅辅助；矩形沿边着色并保留琥珀色局部补线。4×4 OR 汇聚，有界搜索最多8个符合尺寸的候选，选择有效候选中最大的一个。仍是单结果输出。','圆/椭圆验证曲线带、至少一半原始点支持、八方向与四向覆盖；内侧重复描边可不作为外轮廓的离群点计入。矩形使用四边支持、尺度相关边带、角点和内部密度检查。','原视频路径、控制、M0～M6及关键硬件模块/约束不变。原 G1R 和灰度基准源文件与原固件已校验。','','## 实际离线证据','','42帧512×384直接边缘图形测试：圆/横纵椭圆、小圆、多个位置相位、三个方形尺度、4/8/12像素双圆描边、4/12/24像素双矩形描边、较大无效轮廓旁的小椭圆、内部文字、圆弧、密集背景、空白。','4帧1920×1080/2200×1125实际栅格测试：圆、椭圆、矩形和空白。另4帧三角形、菱形、缺30度弧线、小于尺度门槛的圆均输出NONE。','8帧真实RGB→PRE2→Sobel→NMS→连接→识别集成，包含连续椭圆、正方形、矩形、三角形、空白和移动卡；断言ELLIPSE结果以及真实曲线着色像素数。','5种NONE/CIRCLE/SQUARE/RECT/ELLIPSE叠加状态：实际边缘绿色、矩形补线琥珀虚线、内部无关边缘不着色、NONE无目标框、消隐不绘制。','首次VS等待、计算中复位、预算截止与立即VS中断/下一帧恢复测试通过。','7组原视频/控制/同步/异常恢复检查，关闭识别回退、83源公共接口及8项工程元数据测试通过。所有结果与有效框在帧边界更新。','','## 最终资源与时序','','| 项目 | 使用 |','|---|---:|']
 for name,x in resources.items():lines.append(f'| {name} | {x["used"]}/{x["total"]} ({x["percent"]}) |')
 lines+=['',f'最小setup +{tt["min_setup_ns"]:.3f}ns，最小hold +{tt["min_hold_ns"]:.3f}ns；HDMI像素域setup +{tt["hdmi_setup_ns"]:.3f}ns。','Efinity map/interface/pnr/pgm通过；CDC无synchronizer警告。既有未使用接口提示仍存在；报告通过不能替代实板或外部IO验收。','','## 已知限制','','近轴向椭圆、近水平/垂直矩形，轴比不超过3:1；任意旋转、强透视、密集粘连纹理、严重遮挡和多目标同时标注没有实现。不得宣称已普遍识别真实物体。','约一帧结果滞后和4像素级量化；快速移动时着色可能跟不上。曲线着色由真实边缘与上一帧外轮廓走廊共同决定，外侧曲线优先，并非逐个内部描边像素都保证着色。矩形局部补线不改变原始边缘。','逻辑占用约79%，RAM约82%，后续功能仍需重新检查布局资源和时序。早期构建及失败用例不属于最终通过证据。','诊断数字仍为HEX；W/H是量化像素尺寸，不是毫米。','无真实摄像头帧回放与上板测试，不提供实物准确率或长期稳定性结论。','','固件和源码哈希见g2_release_manifest.json，入口见../START_HERE_G2.md。']
 (P/'V11_G2_VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
 print(json.dumps(record,indent=2)[-1900:]);print('G2 RELEASE PASS')
if __name__=='__main__':main()
