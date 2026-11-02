#!/usr/bin/env python3
"""Strict public-interface elaboration: valid, missing FIFO, duplicate FIFO."""
from pathlib import Path
import json, os, subprocess, sys, xml.etree.ElementTree as E
from project_structure import local_name

ROOT = Path(__file__).resolve().parents[1]
compiler = os.environ.get('IVERILOG', 'iverilog')
env = dict(os.environ, IVERILOG=compiler)
subprocess.run([sys.executable, str(ROOT/'scripts/check_project.py')], env=env, check=True)
build = ROOT/'sim/build/board_interfaces'
sources = [e.get('name') for e in E.parse(ROOT/'ti60f225_oob.xml').getroot().iter()
           if local_name(e) == 'design_file']
files = [build/(str(i)+'_'+Path(p).name) for i, p in enumerate(sources)]
fifo = files[sources.index('rtl/frame_buffer_V4/DC_FIFO.v')]
base = [compiler, '-g2012', '-s', 'ti60f225_oob_top', '-o', str(build/'negative.vvp')]
for directory in ['rtl', 'rtl/ddr3_controller', 'rtl/cam_i2c_ctrl/i2c_master']:
    base += ['-I', str(ROOT/directory)]
primitive = build/'device_primitive_interfaces.v'
results = [{'case': 'complete_source_list', 'status': 'PASS'}]
cases = [('missing_shared_fifo', [p for p in files if p != fifo], "Unknown module type: DC_FIFO"),
         ('duplicate_fifo_definition', files+[fifo], "has already been declared")]
for label, inputs, diagnostic in cases:
    result = subprocess.run(base+list(map(str, inputs+[primitive])), cwd=ROOT,
                            text=True, capture_output=True)
    output = result.stdout+result.stderr
    (ROOT/'reports'/('dependency_'+label+'.log')).write_text(output)
    assert result.returncode != 0 and diagnostic in output, (label, output)
    results.append({'case': label, 'status': 'PASS', 'invalid_input_rejected': True,
                    'diagnostic': diagnostic})
(ROOT/'reports/board_dependency_regression.json').write_text(json.dumps(results, indent=2))
print('Strict board dependency regression PASS: 3 cases')
