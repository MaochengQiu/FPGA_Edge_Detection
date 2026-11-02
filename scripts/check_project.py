#!/usr/bin/env python3
"""Check integration against the uploaded user-created empty Efinity project."""
from pathlib import Path
import hashlib,json,os,re,subprocess,xml.etree.ElementTree as E
from project_structure import validate,local_name
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'ti60f225_oob.xml'
r=E.parse(PROJECT).getroot()
blank=E.parse(ROOT/'reference/user_blank_project.xml').getroot()
peri=E.parse(ROOT/'ti60f225_oob.peri.xml').getroot()
report=validate(PROJECT,r,peri)

def shape(e):
    return (e.tag,tuple(sorted(e.attrib.items())),tuple(shape(c) for c in e))

def child(root,name):
    return next(e for e in root if local_name(e)==name)

assert r.attrib==blank.attrib,'User project root metadata changed'
for section in ['device_info','synthesis','place_and_route','bitstream_generation','debugger','security']:
    assert shape(child(r,section))==shape(child(blank,section)), 'User settings changed: '+section
report['user_project_settings_preserved']='PASS'
assert child(child(r,'design_info'),'top_module').get('name')=='ti60f225_oob_top'
assert child(r,'design_info').get('def_veri_version')=='sv_09'
sources=[(ROOT/e.get('name')).resolve() for e in r.iter() if local_name(e)=='design_file']
assert len(sources)==len(set(sources))==83,'Incomplete G1 source list'
assert (ROOT/'rtl/frame_buffer_V4/DC_FIFO.v').resolve() in sources,'CVO shared DC_FIFO dependency omitted'
gpios=[e for e in peri.iter() if local_name(e)=='comp_gpio']
assignments=[e.get('gpio_def') for e in gpios]
assert len(assignments)==len(set(assignments)),'GPIO resource collision'
keys={e.get('name'):e.get('gpio_def') for e in gpios if e.get('bus_name')=='edge_keys_n'}
assert keys=={'edge_keys_n[0]':'GPIOR_22','edge_keys_n[1]':'GPIOR_21','edge_keys_n[2]':'GPIOL_03'}
custom=[];modules=[]
for p in sorted((ROOT/'rtl/edge').glob('*/*.sv')):
    custom.append(p.resolve())
    modules+=re.findall(r'^module\s+(\w+)',p.read_text(),re.M)
assert len(custom)==len(set(modules))==32 and all(p in sources for p in custom)
include_dirs=[ROOT/'rtl',ROOT/'rtl/ddr3_controller',ROOT/'rtl/cam_i2c_ctrl/i2c_master']
for p in sources:
    text=re.sub(r'/\*.*?\*/|//[^\n]*','',p.read_text(errors='replace'),flags=re.S)
    for name in re.findall(r'`include\s+"([^"]+)"',text):
        assert any((d/name).is_file() for d in include_dirs) or (p.parent/name).is_file(),(p,name)
assert (ROOT/'rtl/gamma_conrrection/2P2.mem').is_file()
assert all('<USER_PERIOD>' not in line for line in (ROOT/'ti60f225_oob.sdc').read_text().splitlines() if not line.lstrip().startswith('#'))
report.update(source_files=len(sources),custom_modules=len(modules),GPIOs=len(gpios),pin_collisions='NONE',include_and_memory_paths='PASS',licensed_IP_behavior='NOT VERIFIED')
if os.environ.get('IVERILOG'):
    build=ROOT/'sim/build/board_interfaces';build.mkdir(parents=True,exist_ok=True)
    transformed=[];protected=[]
    for index,p in enumerate(sources):
        s=p.read_text(errors='replace')
        if 'begin_protected' in s:
            protected.append(p.relative_to(ROOT).as_posix())
            prefix=s.split('`pragma protect begin_protected',1)[0]
            prefix=re.sub(r'/\*.*?\*/|//[^\n]*','',prefix,flags=re.S)
            module=re.search(r'^\s*module\s+',prefix,re.M);assert module,p
            depth=0;end=None
            for position in range(module.end(),len(prefix)):
                ch=prefix[position]
                if ch=='(':depth+=1
                elif ch==')':depth-=1
                elif ch==';' and depth==0:end=position+1;break
            assert end,p
            s=prefix[:end]+'\n// Public interface only; not a functional model.\nendmodule\n'
        s=re.sub(r'^.*`pragma.*$','',s,flags=re.M)
        t=build/(str(index)+'_'+p.name);t.write_text(s);transformed.append(t)
    # Only this known device primitive is modeled for interface checking.
    # Do not use -i: every missing project module must fail elaboration.
    primitive=build/'device_primitive_interfaces.v'
    primitive.write_text('module EFX_GBUFCE #(parameter CE_POLARITY=1\'b1)(input wire CE,I,output wire O); endmodule\n')
    transformed.append(primitive)
    command=[os.environ['IVERILOG'],'-g2012','-s','ti60f225_oob_top','-o',str(build/'interfaces.vvp')]
    for directory in include_dirs:command+=['-I',str(directory)]
    command+=list(map(str,transformed))
    if os.environ.get('RTL_SIM')=='icarus_direct':
        from icarus_direct import compile_sources
        result=compile_sources(transformed,'ti60f225_oob_top',build/'interfaces.vvp',ROOT,includes=include_dirs)
    else:
        result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True)
    (ROOT/'reports/board_interface_compile.log').write_text(result.stdout+result.stderr)
    assert result.returncode==0,result.stdout+result.stderr
    report['public_interface_elaboration']='PASS'
    report['unknown_project_modules_allowed']=False
    report['temporary_device_primitive_models']=['EFX_GBUFCE']
    report['protected_source_files']=protected
(ROOT/'reports/project_checks.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
