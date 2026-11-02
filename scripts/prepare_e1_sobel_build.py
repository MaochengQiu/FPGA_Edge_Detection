"""Isolated build cache for an immediately programmable E1 Sobel A/B image.
The delivered E1 source stays NMS-on. Only the top parameter differs here.
"""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
dest=ROOT/'work/sobel'
assert not (dest/'ti60f225_oob.xml').exists(),'Preserve existing A/B build'
dest.mkdir(parents=True,exist_ok=True)
for name in ('rtl','ip','ooc'):
    if (ROOT/name).is_dir() and not (dest/name).exists():shutil.copytree(ROOT/name,dest/name)
for f in ROOT.iterdir():
    if f.is_file():
        shutil.copy2(f,dest/f.name)
top=dest/'rtl/ti60f225_oob_top.v'
text=top.read_bytes()
assert b"parameter E1_NMS_ENABLE = 1'b1" in text
top.write_bytes(text.replace(b"parameter E1_NMS_ENABLE = 1'b1",b"parameter E1_NMS_ENABLE = 1'b0"))
work=dest/'work';work.mkdir(exist_ok=True)
(work/'efinity_user.ini').write_text('[General]\nEFINITY_USER_DIR='+work.as_posix()+'/efinity_user\n',encoding='ascii')
print(dest)
