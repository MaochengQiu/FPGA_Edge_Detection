from pathlib import Path
import hashlib,json,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def xml_node(n):return [n.tag,sorted(n.attrib.items()),[xml_node(c) for c in n]]
def snapshot():
 tree=ET.parse(ROOT/'ti60f225_oob.xml').getroot()
 files=[n.get('name') for n in tree.iter() if n.tag.endswith('design_file')]
 files+=['ti60f225_oob.sdc','ti60f225_oob.peri.xml','rtl/gamma_conrrection/2P2.mem']
 return dict(source_sha256={n:sha(ROOT/n) for n in files},project_semantic_sha256=hashlib.sha256(json.dumps(xml_node(tree)).encode()).hexdigest())
if __name__=='__main__':
 p=ROOT/'reports/g1r_build_inputs.json';actual=snapshot()
 if '--check' in sys.argv:
  assert actual==json.loads(p.read_text()),'Build source changed during compilation'
  print('G1R build source snapshot MATCH')
 else:
  p.write_text(json.dumps(actual,indent=2));print('G1R build source snapshot recorded')
