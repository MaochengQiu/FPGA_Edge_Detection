from pathlib import Path
import shutil

root=Path(__file__).resolve().parents[1]
dest=root/'work/hdmi_test_release'
assert not dest.exists(),'Preserve prior test build'
dest.mkdir(parents=True)
for name in ('rtl','ip','ooc'):shutil.copytree(root/name,dest/name)
for p in root.iterdir():
    if p.is_file():shutil.copy2(p,dest/p.name)
top=dest/'rtl/ti60f225_oob_top.v';data=top.read_bytes()
old=b"E4_HDMI_TEST = 1'b0";assert data.count(old)==1
top.write_bytes(data.replace(old,b"E4_HDMI_TEST = 1'b1"))
print(dest)
