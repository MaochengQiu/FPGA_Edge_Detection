#!/usr/bin/env python3
"""Check fixed metadata and reject examples of the actual v1 packaging defects."""
from pathlib import Path
from copy import deepcopy
import json
import xml.etree.ElementTree as E
from project_structure import validate, local_name

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'ti60f225_oob.xml'
r = E.parse(PROJECT).getroot()
p = E.parse(PROJECT.with_suffix('.peri.xml')).getroot()
results = [{'case': 'fixed_project', 'status': 'PASS', **validate(PROJECT, r, p)}]

def reject(label, mutate):
    a, b = deepcopy(r), deepcopy(p)
    mutate(a, b)
    try:
        validate(PROJECT, a, b)
    except AssertionError as error:
        results.append({'case': label, 'status': 'PASS', 'rejected_reason': str(error)})
    else:
        raise AssertionError('Invalid metadata accepted: ' + label)

def source(a):
    return next(e for e in a.iter() if local_name(e) == 'design_file')

def misplaced_source(a, b):
    design = next(e for e in a if local_name(e) == 'design_info')
    e = source(a)
    design.remove(e)
    design.append(e)

def misplaced_gpio(a, b):
    gpio = next(e for e in b if local_name(e) == 'gpio_info')
    e = next(e for e in gpio if local_name(e) == 'comp_gpio')
    gpio.remove(e)
    gpio.append(e)

reject('v1_project_name_mismatch', lambda a, b: a.set('name', 'ti60_edge_v1'))
reject('peripheral_name_mismatch', lambda a, b: b.set('name', 'wrong_project'))
reject('v1_design_file_after_metadata', misplaced_source)
reject('v1_GPIO_after_bus', misplaced_gpio)
reject('external_source_path', lambda a, b: source(a).set('name', '../../rtl/top/img_pipeline.sv'))
reject('missing_source', lambda a, b: source(a).set('name', 'rtl/not_present.v'))
reject('device_mismatch', lambda a, b: b.set('device_def', 'Ti120F576'))
(ROOT / 'reports/project_structure_regression.json').write_text(json.dumps(results, indent=2))
print(f'Project metadata regression PASS: {len(results)} cases')
