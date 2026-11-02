"""Demo-derived structural checks; not a replacement for Efinity's own XSD/GUI."""
from pathlib import Path

def local_name(element):
    return element.tag.split('}')[-1]

def validate(project, root, peri):
    project = Path(project).resolve()
    folder = project.parent
    assert root.get('name') == project.stem, 'Project name differs from XML filename'
    assert peri.get('name') == root.get('name'), 'Peripheral and project names differ'
    design = next(e for e in root if local_name(e) == 'design_info')
    tags = [local_name(e) for e in design]
    assert tags[0] == 'top_module', 'top_module must come first as in demo'
    phase = 0
    for tag in tags[1:]:
        if tag == 'design_file':
            assert phase == 0, 'design_file follows trailing design metadata'
        else:
            phase = 1
    gpio = next(e for e in peri if local_name(e) == 'gpio_info')
    rank = {'comp_gpio': 0, 'global_unused_config': 1, 'bus': 2}
    sequence = [rank[local_name(e)] for e in gpio]
    assert sequence == sorted(sequence), 'GPIO child groups differ from demo order'
    assert sum(local_name(e) == 'global_unused_config' for e in gpio) == 1
    device = next(e.get('name') for e in root.iter() if local_name(e) == 'device')
    assert peri.get('device_def') == device, 'Peripheral and project devices differ'
    for e in root.iter():
        if local_name(e) in ('design_file', 'default_peri_file', 'peri_file', 'sdc_file'):
            name = e.get('name', '')
            path = (folder / name).resolve()
            assert name and not Path(name).is_absolute(), f'Nonportable path: {name}'
            assert path.is_relative_to(folder), f'Path escapes board project: {name}'
            assert path.is_file(), f'Missing project file: {name}'
    return {'project_identity': 'PASS', 'demo_child_order': 'PASS',
            'self_contained_paths': 'PASS', 'device_consistency': 'PASS',
            'Efinity_XSD_and_GUI': 'NOT VERIFIED'}
