from pathlib import Path
import shutil

root=Path(__file__).resolve().parents[1]
dest=root/'work/baseline_release'
assert not dest.exists(),'Preserve prior build evidence'
dest.mkdir(parents=True)
for name in ('rtl','ip','ooc'):
    shutil.copytree(root/name,dest/name)
for file in root.iterdir():
    if file.is_file():shutil.copy2(file,dest/file.name)
top=dest/'rtl/ti60f225_oob_top.v'
text=top.read_bytes()
old=b"E3_WEAK_CHAIN_ENABLE = 1'b1"
assert text.count(old)==1
top.write_bytes(text.replace(old,b"E3_WEAK_CHAIN_ENABLE = 1'b0"))
print(dest)
