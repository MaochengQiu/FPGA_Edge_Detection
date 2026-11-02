# Ti60F225 赛题四 — V10-C2 色彩相位修正版

直接在现有 V10 工程中修改，入口仍为 `ti60f225_oob.xml`。C2 仍处于第一步色彩优化，边缘算法优化尚未开始。没有新建工程或重构视频架构；DDR、MIPI、HDMI、PLL、复位、摄像头曝光和配置表保持不变。

本版烧录 `programming/ti60f225_oob_V10_C2.bit`。M6 第一行显示 **C2 RAW**，第四行显示 **C2 RAW1X CLIP** 和 PH；下方有固定的红、绿、蓝、白、黑参考色块。原 C1/V10 固件和完整包均保留。

## 此次色彩修改

- C1 固定 GRBG 的假设未能确认实板颜色排列。C2 支持四种第一像素 Bayer 排列，按键选择，在帧消隐期间应用，不重启视频。
- RGB 增益上电改为 `100/100/100`（各 1 倍），不再套用历史绿色大幅补偿。RAW 精确 1 倍、后级舍入/饱和、裁剪计数和 1/32 增益步进继续保留。
- 沿用 Debayer 行缓存、窗口和寄存器时序，仅扩展颜色位置及插值方向的选择。灰度、Sobel、预处理和合成 RTL 均未改动。
- M6 固定参考色块在最终阶段直接产生，帮助分辨摄像头色彩问题与显示端问题。

**PH:1 RGGB 只是待验证的上电起点，尚未确定实板实际相位。** 操作及测试要求见 [V10_C2_COLOR.md](docs/V10_C2_COLOR.md)；真实编译、仿真和时序结果见 [V10_C2_VALIDATION.md](reports/V10_C2_VALIDATION.md)。

## 上板操作

1. 上电 M3，短按 KEY3 三次到 M6，确认 C2 标记和默认增益 `R:100 G:100 B:100`。
2. 确认五个固定色块从左到右为红、绿、蓝、白、黑。
3. 将真实红/绿/蓝物体放在相机前，M6 长按 KEY3 每次约一秒并释放，调节对象依次 `R → G → B → P → R`。
4. `SEL:P` 时 KEY1/KEY2 前进/后退 PH：`0 GRBG → 1 RGGB → 2 BGGR → 3 GBRG`。以三种实际颜色均对应正确为准；相位设置不自动保存，复位恢复 PH:1。
5. 确定相位后再用白/灰卡调 R/G/B 增益，不用白平衡掩盖相位错误。请反馈正确 PH、固定色块是否正确，以及白/灰卡 RAW/OUT/GAIN/CLIP。

## 模式与原功能

模式编号保留：M0 彩色；M1 灰度；M2 最终二值边缘；M3 左彩色原图/右二值边缘，整幅图横向抽样对比；M4 红色轮廓叠加；M5 梯度幅值灰度预览；M6 彩色调试页。M5 不经过二值化，调二值阈值不会改变它的梯度图像。

KEY3 短按仍按 `3→4→5→6→0→1→2→3` 循环。除 M6 外，KEY1/KEY2 调阈值，范围 4～128、默认 24、步进 1，长按约 0.5 秒后每 0.1 秒变化 1，饱和保持而不回绕。其他页长按 KEY3 切旁路/中值/高斯/细节增强。M6 的 R/G/B 增益调节仍是 1/32，范围 0.5～2.25。KEY1+KEY2 仍冻结/解冻，KEY0 仍复位。

M6 RAW/OUT 是中央区域 256 个抽样点的白平衡前/后均值，不是相机寄存器。CLIP 为该采样点中后级增益溢出次数，十六进制 `100` 为 256。增益和相位应用于完整帧；显示 PH 为 Debayer 已应用的值。极高阈值可能使二值区域全黑，HDMI 和参数条仍应保持。

## 稳定性与帧率

保留 V9/V10 的连续显示时序、三帧缓存、最新完整帧策略、4 个在途写响应、忙读请求保留、2048 深度捕获/显示 FIFO、溢出及读错诊断。C2 不改这些结构。

HDMI 为 1080p60。CAM/DDR/SCREEN 是按 60 个输出周期统计的相机帧/写入帧/选中新帧，不是 HDMI 刷新率。源端约 30 个新帧时会重复完整帧；本轮未更改摄像头帧率或曝光。

## 编译与验证

在 Efinity 中打开 `ti60f225_oob.xml`，完整编译使用 `efx_run ti60f225_oob.xml --flow compile`。`full` 会额外调用尚未配置的工程级 IP 仿真，不用于这里的完整编译流程。

- `scripts/check_c2_scope.py`：与 C1 发布清单比较，确认仅五个色彩 RTL 文件改变，顶层其他连线和项目设置不变。
- `scripts/check_project.py`、`scripts/test_project_structure.py`：工程及接口检查。
- `scripts/run_tests.py`：完整回归，可选择 Icarus 或 ModelSim；本机使用 `D:\Codex\FPGA\tools\iverilog\bin` 中的 Icarus。新增四种排列及帧切换测试，其余稳定性测试保留。
- `scripts/finalize_c2.py`：只有真实回归、编译和最终时序通过后，才收集独立 C2 烧录文件、验证报告及 SHA256 清单。
- `scripts/package_c2.py`：验证清单，生成 `version/packages/ti60f225_oob_V10_C2_color.zip`。默认拒绝覆盖已有包。

综合/布局布线包含实际加密 IP；开源仿真中的加密模块接口检查仅证明连线，不替代加密 IP 功能验证。数字逻辑测试和时序检查不能代替 C2 实板颜色标定及长期运行测试。

## 回退与目录

- `rtl` 工程源文件；`sim` 测试；`scripts` 构建和验证；`reports` 日志/清单；`docs` 操作说明；`programming` 烧录文件。
- C1 回退：`programming/ti60f225_oob_V10_C1.bit`、`reference/c2_baseline/rtl`、`version/packages/ti60f225_oob_V10_C1_color.zip`。
- V10 回退：`programming/ti60f225_oob_V10.bit`、`reference/c1_baseline/V10_source_before_C1.zip`。
- V10/C1 的旧说明和脚本作为历史保留。它们的固定白卡预设和旧发布入口不适用于当前 C2，使用本页所列 C2 入口。
