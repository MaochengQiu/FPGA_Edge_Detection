"""Make a separate E2N build cache; only E2_LINK_ENABLE differs from E2L."""
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
dest=ROOT/'work/nms_release'
assert not dest.exists(),'Preserve the existing A/B build cache'
dest.mkdir(parents=True)
for name in ('rtl','ip','ooc'):
    if (ROOT/name).is_dir():shutil.copytree(ROOT/name,dest/name)
for f in ROOT.iterdir():
    if f.is_file():shutil.copy2(f,dest/f.name)
top=dest/'rtl/ti60f225_oob_top.v'
text=top.read_bytes()
old=b"parameter E2_LINK_ENABLE = 1'b1"
assert text.count(old)==1
top.write_bytes(text.replace(old,b"parameter E2_LINK_ENABLE = 1'b0"))
work=dest/'work';work.mkdir()
(work/'efinity_user.ini').write_text('[General]\nEFINITY_USER_DIR='+work.as_posix()+'/efinity_user\n',encoding='ascii')
print(dest)
