# Ti60F225 赛题四 — V10-C1 色彩优化

本版直接在现有 V10 工程中修改，入口仍为 `ti60f225_oob.xml`，工程身份、硬件接口和视频架构不变。C1只处理色彩：修正一处Debayer红蓝插值邻域接反；RAW前级精确1倍，后级统一白平衡；四舍五入和饱和；M6增益步进1/32及ROI裁剪统计。操作及实板验收见 `docs/V10_C1_COLOR.md`，验证见 `reports/V10_C1_VALIDATION.md`。灰度/Sobel/NMS等边缘算法本轮不改，等待实板反馈。

V10完整回退源码保存在 `reference/c1_baseline/V10_source_before_C1.zip`；原 `programming/ti60f225_oob_V10.bit` 保留。C1必须烧 `programming/ti60f225_oob_V10_C1.bit`。参数条同时出现V10及C1标记，M6第四行显示 `C1 RAW1X CLIP`。

## 历史白卡预设（C1需重新校准）

- Uncorrected sample: RGB = `F4 / 6A / C4` (decimal 244 / 106 / 196).
- New gain preset in Q8 format (0x100=1.0): `R=0C0`, `G=1C0`, `B=0F0`.
- 以上是修正Debayer前的历史样本。C1保留增益作为调试起点，不能认为它已适用于修正后的相机数据。
- 对同一组旧输入做C1舍入运算，数学输出为 `B7 / BA / B8`（183/186/184）；这不是C1实测颜色。
- 请用白/灰卡重新确认RAW/OUT和CLIP；不要用人脸、彩色纸杯的均值做白平衡目标。C1没有自动白平衡或色卡标定结果。

## HDMI modes and buttons

- **上电模式3**：左原图/右最终二值边缘，保留小型参数条。
- **模式0/1**：彩色/灰度原图；阈值不改变这两个页面的图像。
- **模式2**：最终二值 Sobel；**模式5**：梯度幅值预览，没有经过二值阈值筛选，调阈值不改变模式5的梯度画面。
- **模式0～5参数条**：`V10 M:2 T:024 MAX:128 S:1`。T 是十进制，到顶显示黄色 MAX，到底显示 MIN。黑色边缘背景不影响参数条。
- **模式6**：完整白平衡、帧率及 U/D/R/L/O 诊断；T 同样改为十进制，其他 RGB/GAIN 值仍为十六进制。
- KEY3短按循环0～6，上电M3短按三次到M6。M6长按KEY3选R/G/B，KEY1/2增减所选增益，C1步进 **1/32（Q8=008）**，范围0.5～2.25。阈值、冻结和其他页面操作与V10相同。

上电模式3，KEY3 短按顺序为 `3→4→5→6→0→1→2→3`。除模式6外，KEY1 增阈值、KEY2 减阈值，**范围4～128，默认24，步进1**。长按约0.5秒后每0.1秒调整1。到上下限后保持数值，不回绕；host 写入也经过同样的限制；下一帧生效。模式6的 KEY1/2 仍调白平衡增益。

其他页面长按 KEY3 依次切换旁路、中值、高斯和细节增强。KEY1+KEY2 同按冻结；KEY0 整板复位。RGB 增益仍作用于全部模式。

暗部弱边缘先用 KEY2 从24逐步降至20、16、12观察；KEY1 增大会减少边缘。128是手动调节的实用上限，不保证任何场景都检出边缘。均匀或缺乏对比的图像仍可全黑，但参数条和 HDMI 同步应保持。

## 沿用 V9 的稳定性结构

- 连续 `img_video_out` 替代原 CVO：数据不足时填黑、丢弃受损帧尾，在下一 SOF/有效帧边界恢复；数据是否可用不改变 HS/VS/DE 周期。
- DDR reader 忙时保留一项请求；writer 最多 4 个 B 响应在途，全部成功后才发布帧。三缓冲最新完整帧策略保留。
- 捕获、显示异步 FIFO 各加深到 2048 个 AXI128 word；溢出改成源端单比特锁存后同步，补齐诊断第一拍 CDC 约束。
- 摄像头 stream-on 移到配置表最后，几何/增益在停流时完成；PLL、HTS/VTS 和 MIPI 速率保持原配置。

## Frame-rate interpretation

用户 V8 实测照片为 `CAM:30 DDR:30 SCREEN:30`。这些是每 60 个 HDMI 输出帧中的摄像头帧、成功写入帧、选中的新帧数；**SCREEN 不是 HDMI 刷新率**。本版 HDMI 保持 1080p60。源端每秒提供约 30 帧时，会重复完整帧。DDR 优化改善吞吐和抗抖动；要真正将摄像头提高到 60 fps，还需要与当前 SC431HAI 模组匹配、经过实板验证的 1080p60 寄存器表。

## Build

Open `ti60f225_oob.xml` in Efinity and run synthesis, Interface Designer, place/route, timing analysis and bitstream generation. CLI: `efx_run ti60f225_oob.xml --flow compile`. Efinity's `full` flow also invokes unconfigured project-level IP simulation; use `compile` for the complete programming-file build.

本版烧录文件为 `programming/ti60f225_oob_V10_C1.bit`，SHA256在 `reports/v10_c1_release_manifest.json`。烧入后参数条显示V10与C1，M6第四行显示RAW1X及CLIP。更改RTL后必须重新编译；只生成C1产物请用 `scripts/finalize_c1.py`、`scripts/package_c1.py`，旧V10发布脚本只作历史保留。

## Validation status

Run `python scripts/run_tests.py` for the full regression; set `IVERILOG`/`VVP` for Icarus, or `RTL_SIM=modelsim` and `MODELSIM_BIN` for a licensed ModelSim/Questa. Actual C1 results: `reports/V10_C1_VALIDATION.md`. `scripts/check_c1_scope.py` compares source/settings against the delivered V10 and exports the color-only diff. Software tests do not replace board-level color/HDMI/camera acceptance.

See [`docs/V8_WB_CALIBRATION.md`](docs/V8_WB_CALIBRATION.md) for details.
