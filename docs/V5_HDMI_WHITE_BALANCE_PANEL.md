# V5 HDMI 相机白平衡 / 实时参数诊断页

## 版本用途
本版针对“直通画面偏紫，缺少可视化参数反馈”的问题。**不改变 Ti60F225 开发板物理引脚、IO 电压、PLL、DDR3 控制器、MIPI 接口及 HDMI 输出时序**。继续保留 V4 的 Sobel、左右完整视野对比和摄像头/DDR/显示端 C/d/S 计数。

## 操作指南（KEY0 仍为复位）
- 上电默认显示模式 3（左彩色视频，右 Sobel 边缘图）；短按 **KEY3 三次**：模式 3→4→5→6，进入诊断页。再短按 KEY3：模式 6→0，以后依次 1、2、3。各模式：0=彩色、1=灰度、2=二值边缘、3=对比分屏、4=彩色边缘叠加、5=梯度灰度、6=参数诊断。
- 非诊断页：KEY1、KEY2 继续分别 **Sobel 阈值 +8 / -8**；长按 KEY3 继续依次切换 0直通、1中值、2Gaussian、3细节锐化。
- **诊断页（模式6）**：长按 KEY3 一次，`SEL` 从 0（R）→1（G）→2（B）→0 循环；KEY1 选中通道增益 **+0x010**，KEY2 **-0x010**。三个增益范围 `0x080`～`0x180`，默认 `0x100`（1.000x）；按增益乘 Q8.8 计算，输出作 8 位饱和。离开诊断页后已设定增益继续作用于彩色输出和边缘检测输入；重新复位后回到 1.0x。
- 同时按 KEY1+KEY2：保留 V4 画面冻结切换功能。不要长按错按 KEY0（会复位所有设置）。

## HDMI 面板每项的含义
- `RAW R/G/B`: Debayer **之后**、新增颜色校正**之前**，ROI 的 8-bit R/G/B 采样平均值。显示为**十六进制** `00~FF`。
- `OUTPUT R/G/B`: 同一个采样位置，新增颜色校正**之后**的 RGB 采样均值，同样十六进制。注意此数值位于可选 gamma 模块之前。
- `SAMPLES`: 每帧中央区域 16×16 共 **256 个采样点**，正常应显示 `100`（十六进制 256）。`VALID=1` 表示上一完整帧采样数量正确。若 `VALID=0`，本次 RAW/OUTPUT 均值不更新，不能据此校准。
- `GAINS Q8.8`: 新增 **post-Debayer** R/G/B 独立增益，`100` = 1.0x，`0C0` = 0.75x，`140`=1.25x。
- `SEL`: 当前被 KEY1/KEY2 调节的通道，0=R、1=G、2=B。
- `SOBEL T`: 当前待生效 Sobel 阈值（十六进制，默认 `028`=十进制40）。`FILTER` 0直通、1中值、2Gaussian、3细节锐化。`MODE` 6 表示诊断页。
- `CAM`, `DDR`, `SCREEN`: 来自 V4 的帧事件计数，分别是相机帧事件、AXI成功完成整帧写入和显示端新选中帧数。单位均为**每 60 个 HDMI VS 周期的事件数**（十进制两位 BCD），**仅在 HDMI 实际为 60Hz 时才近似 FPS**，不会直接测量端到端延迟。
- `PRESSES`, `LAST KEY`: 物理按键识别次数（低 8 位十六进制）及最后按键 1/2/3。
- `HOLD`: 冻结状态，`FAULT REJ/LATE/FIFO`：DDR 拒绝帧 / 延迟读取请求 / 采集 FIFO 溢出状态（0/1，异常位部分是上电后的 sticky 状态）。
- 右侧矩形为**同一实时视频流的未缩放局部预览**，不是独立相机流或另一个帧缓存。若画面刷新滞后，此处也会滞后。

## 用白卡校准的方法
1. 固定摄像头与照明，选择不反光、无文字、不过曝的白色/中性灰色纸张放在画面**正中央**；尽量填满中央半幅面积。
2. 进入诊断页，确认 `SAMPLES:100 VALID:1`。拍一张同时包含 RAW、OUTPUT 和增益值的照片。
3. 先看 `RAW`：如果 R、B 明显高于 G，可能表现为紫色偏色。先选 `G` 加增益，或分别选 `R/B` 降增益，逐步调节，使 `OUTPUT R/G/B` 接近。切勿直接把白卡调到 `FF FF FF`（过曝无法判别色偏）。
4. 退回模式0检查真实彩色图像，再回模式3查看边缘检测。此校准只作用于数字 RGB；若色偏源于错误的 Bayer 格式、通道交换或传感器内部 ISP，单靠增益可能无法彻底解决。
5. 若 JTAG VIO 使用了原来 `vio0_r/g/b_gain`，原 Bayer 增益仍会生效，并与新的 post-Debayer 增益叠加。建议校准时先保证原来的三个 raw gains 处于 unity 附近（原工程的 0 值走回退 0xFF），`gamma_sel` 关闭，以免造成混淆。本版没有虚构传感器内部 AWB、曝光、模拟增益或实际寄存器读回值。

## 软件代码位置
- `rtl/edge/control/img_control.sv`：KEY3 的模式6，RGB 选择与增益调节；KEY1/2 原阈值逻辑保留。
- `rtl/edge/compose/edge_color_balance.sv`：Debayer 之后的 RGB8 Q8.8 乘法及饱和（1周期，DE/HS/VS同步延迟）。
- `rtl/edge/compose/edge_rgb_statistics.sv`：中央16×16网格的 RAW/OUTPUT 对齐统计（只显示有完整 256 个样本的帧）。
- `rtl/edge/compose/edge_diag_page.sv`：1080p HDMI 字符点阵面板，右侧实时预览（1周期，DE/HS/VS同步延迟）。
- `rtl/edge/compose/edge_video_health.sv`：导出原有 C/d/S 和异常标志以便诊断页读取；**没有改变帧缓存算法**。
- `rtl/ti60f225_oob_top.v`：连接上述模块；`ti60f225_oob.xml`：登记 RTL 源码（不是改变板级硬件配置）。

## 当前验证边界
已运行：Python 静态完整工程清单检查、原有曝光参数和工程配置参考检查、离线 RGB Q8.8 数学参考、256点采样数学测试；诊断页按1920×1080布局离线渲染检查。已提供 Icarus RTL testbench：`sim/tb_white_balance.sv`、`sim/tb_rgb_statistics.sv`、`sim/tb_control_white_balance.sv`，执行 `python scripts/run_tests.py` 需 `iverilog` 和 `vvp`。**本运行环境没有可用的 Verilog 仿真器或 Efinity，因此这些 testbench 并未在此执行，也没有时序收敛或上板实测证据。**

若 Efinity 提示时序/资源错误，优先检查新增 RGB 乘法器和字符生成器，不要更改 DDR/MIPI/HDMI 引脚电压或 PLL 作为“修复”。此版本也不声称提高 FPS 或消除了旧 DDR 整帧更新延迟。
