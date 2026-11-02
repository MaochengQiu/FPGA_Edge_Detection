from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parents[3]/'tools/python_libs'))
import numpy as np
from PIL import Image
from verify_e1 import sobel,topology
from e2_model import descriptor,local_link

rows=[]
for name in ('checker','cup_pattern','printed_text','pcb_tracks','face_photo','motion_0'):
    im=Image.open(ROOT/'reference/e1_inputs'/f'{name}.png').resize((128,96))
    m,d,v,k=sobel(im);a,c,s,dr=descriptor(m,d,k,50);out=local_link(a,c,s,dr)
    row=dict(name=name,nms50=topology(k&(m>=50)),e2=topology(out));rows.append(row)
    print(name,row['nms50'],row['e2'])
(ROOT/'reports/e2_model_probe.json').write_text(json.dumps(rows,indent=2))
