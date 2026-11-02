from pathlib import Path
import hashlib,json,re,shutil,sys,xml.etree.ElementTree as ET
from finalize_e3 import timing
r=Path(__file__).resolve().parents[1];o=r.parents[1]/'v11-gray-baseline/ti60f225_oob'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 base=json.loads((o/'reports/baseline_release_manifest.json').read_text(encoding='utf8'))
 for n,h in base['source_sha256'].items():assert sha(o/n)==h,('baseline source modified',n)
 for a in base['artifacts']:assert sha(Path(a['path']))==a['sha256']
 changed=[n for n in base['source_sha256'] if sha(r/n)!=base['source_sha256'][n]]
 assert set(changed)=={'rtl/edge/top/img_pipeline.sv','rtl/edge/compose/img_composer.sv','rtl/edge/compose/edge_final_hud.sv','rtl/ti60f225_oob_top.v'}
 for n in ('ti60f225_oob.sdc','ti60f225_oob.peri.xml'):assert sha(r/n)==sha(o/n)
 assert sha(r/'reference/M7_baseline_img_composer.sv')==sha(o/'rtl/edge/compose/img_composer.sv')
 for f,s in [('g1_shapes.log','G1 SHAPES PASS'),('g1_rgb.log','G1 RGB PASS'),('g1_overlay.log','G1 OVERLAY PASS'),('g1_disabled.log','G1 DISABLED VERIFICATION PASS'),('g1_core.log','G1 CORE VERIFICATION PASS: 7')]:assert s in (r/'reports'/f).read_text(encoding='utf8'),f
 p=json.loads((r/'reports/project_checks.json').read_text());assert p['source_files']==83 and p['public_interface_elaboration']=='PASS'
 assert 'Project metadata regression PASS: 8 cases' in (r/'reports/g1_structure.log').read_text(encoding='utf8')
 build=(r/'reports/efinity_g1_compile.log').read_text(encoding='utf8')
 for s in ('map','interface','pnr','pgm'):assert re.search(r'\b'+s+r'\s*:\s*PASS',build)
 t=timing(r/'outflow/ti60f225_oob.timing.rpt');assert 'No Synchronizer warnings to report.' in (r/'outflow/ti60f225_oob.cdc.rpt').read_text()
 resources={}
 for k in ('XLRs','Memory Blocks','DSP Blocks'):
  m=re.search(r'^'+k+r':\s*(\d+) / (\d+) \(([^)]+)\)',(r/'outflow/ti60f225_oob.place.rpt').read_text(),re.M);assert m
  resources[k]=dict(used=int(m[1]),available=int(m[2]),percent=m[3])
 for ext in ('timing.rpt','place.rpt','hier_util.rpt','cdc.rpt','map.rpt','log','warn.log','err.log'):shutil.copy2(r/f'outflow/ti60f225_oob.{ext}',r/f'reports/g1_{ext}')
 archive=r/'reference/gray_baseline_firmware';archive.mkdir(exist_ok=True)
 for p in (r/'programming').iterdir():
  if p.is_file() and '_V11_G1' not in p.name:
   dest=archive/p.name;assert p.resolve().is_relative_to(r) and dest.resolve().is_relative_to(r)
   assert not dest.exists() or sha(dest)==sha(p)
   if not dest.exists():shutil.move(str(p),str(dest))
 art=[]
 for ext in ('bit','hex'):
  src=r/f'outflow/ti60f225_oob.{ext}';dst=r/f'programming/ti60f225_oob_V11_G1.{ext}'
  assert src.stat().st_size>0 and (not dst.exists() or sha(dst)==sha(src));shutil.copy2(src,dst)
  art.append(dict(path=dst.relative_to(r).as_posix(),sha256=sha(dst),bytes=dst.stat().st_size))
 text='# V11-G1 实际验证与修改清单\n\n状态：离线、实际编译与最终STA通过；无实板验收结论。\n\n基准v11-gray-baseline源码81项及原bit/hex校验保持。修改四项RTL：'+str(changed)+'；新增img_geometry.sv、img_geometry_overlay.sv，工程仅添加这两个源节点；原M7实现冻结在reference。DDR/MIPI/相机/PLL/编码器/引脚/复位逻辑及约束保持。\n\n'
 text+='最终边缘使用final_edge=debug_edge及同拍final_token控制，预composer分支；叠加与RGB经同一个composer寄存器。M0～M6保持，M7改彩色视频识别页。识别结果在VS提交，是上一完成输出帧的结果，移动时允许一帧结果滞后，框有8像素级量化。核心视频延迟不增加。关闭支路恢复旧M7；未完成或不确定输出NONE且视频继续。\n\n'
 text+='实际测试：14帧直接边缘分类/尺寸/移动坐标与帧内稳定；7帧实际RGB滤波/NMS/连接集成；4种输出标签/绿色标记/NONE无虚框；关闭支路回退；7组双核心/控制/HUD/恢复测试含1920列。83源结构/公开端口及8元数据案例通过。旧报告不作为本轮新结果。测试台长移位计分板已改环形数组加速，未改变待测RTL。\n\n'
 text+='|资源|基准|G1|\n|---|---:|---:|\n'
 for k,v in resources.items():text+=f'|{k}|{base["resources"][k]["used"]}|{v["used"]}/{v["available"]} ({v["percent"]})|\n'
 text+=f'\n全设计最小setup +{t["min_setup_ns"]:.3f}ns、hold +{t["min_hold_ns"]:.3f}ns，HDMI像素域setup +{t["hdmi_setup_ns"]:.3f}ns。基准setup {base["timing"]["min_setup_ns"]}ns、HDMI {base["timing"]["hdmi_setup_ns"]}ns。Efinity map/interface/pnr/pgm全部PASS、CDC无同步器警告，未删约束。静态结果不替代外部IO/显示稳定性验证。\n\n'
 text+='中央单目标ROI、OR汇聚和形状判据/容差详见docs/V11_G1.md。对所有残缺形状、复杂噪声和任意旋转不保证；小于汇聚块的缺口可能被OR掩盖。没有CCL/Hough/人脸识别。下一步按M7、同PRE/T对真实圆卡/方卡/矩形卡、移动和NONE背景上板验证，不能把合成PASS冒充实物识别准确率。\n'
 (r/'reports/V11_G1_VALIDATION.md').write_text(text,encoding='utf8')
 sources=[e.get('name') for e in ET.parse(r/'ti60f225_oob.xml').getroot().iter() if e.tag.endswith('design_file')]
 record=dict(status='OFFLINE_AND_BUILD_PASS_AWAITING_BOARD',revision='V11-G1',marker='EGR',baseline_preserved=True,baseline=str(o),modified_rtl=changed,new_rtl=['rtl/edge/geometry/img_geometry.sv','rtl/edge/geometry/img_geometry_overlay.sv'],resources=resources,timing=t,artifacts=art,source_sha256={n:sha(r/n) for n in sources})
 (r/'reports/g1_release_manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(record,ensure_ascii=False,indent=2)[:1800])
if __name__=='__main__':main()
