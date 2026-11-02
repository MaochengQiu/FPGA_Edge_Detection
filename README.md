# FPGA 实时边缘检测与几何识别 · V11-G2

基于易灵思 Titanium Ti60F225 的摄像头实时图像处理工程，使用可综合 Verilog/SystemVerilog 实现 Sobel、非极大值抑制（NMS）、边缘连接和轻量几何识别，经 HDMI 输出。

本仓库采用最后交付的 V11-G2。斜视矩形及双目标 G3 仅讨论了方案，尚未实现。

## 显示模式

| 模式 | 内容 |
| --- | --- |
| M0 | 彩色原图 |
| M1 | 灰度图 |
| M2 | 二值边缘 |
| M3 | 左灰度、右二值边缘 |
| M4 | 彩色原图叠加红色边缘 |
| M5 | 梯度幅值灰度图 |
| M6 | 诊断与白平衡调参 |
| M7 | 彩色背景下的几何识别与轮廓着色 |

M7 支持 CIRCLE、ELLIPSE、SQUARE、RECT、NONE。圆/椭圆真实边缘显示绿色；矩形显示绿色轮廓，有限缺口采用琥珀色虚线补线。中心十字仅为辅助。识别复用最终边缘结果的独立支路，不依赖 PC/OpenCV 或训练模型。

## 目录

```text
rtl/                  视频链路、边缘算法、控制与识别 RTL
  edge/geometry/      候选提取、分类、轮廓叠加
  edge/top/           流水线集成
ip/                   原工程 IP 与配置
reference/            回退参考实现
docs/                 工程说明
sim/                  RTL 测试平台与数据
scripts/              仿真、检查、编译与原发布脚本
test_cards/           SVG 测试卡
programming/          最终 G2 .bit / .hex
reports/              原交付资源、时序与验证证据
ti60f225_oob.xml       Efinity 工程入口
ti60f225_oob.peri.xml  外设与引脚配置
ti60f225_oob.sdc       时序约束
NOTICE.txt            第三方权利说明
UPLOAD_MANIFEST.json  整理后的文件校验清单
```

## 打开与烧录

已验证工具为 Efinity 2026.1.132，器件 Ti60F225、时序模型 I3，顶层 `ti60f225_oob_top`。需要匹配原工程的开发板、摄像头与连接，本工程不能直接适配任意硬件。

在 Efinity 打开根目录 `ti60f225_oob.xml`，沿用现有外设配置和约束编译。通过 Efinity Programmer 烧录 `programming/ti60f225_oob_V11_G2.bit`，同时提供 HEX。

进入 M7 确认 HUD 为 G2。建议先用 PRE2 和设备上已调好的阈值，将完整目标置于中央灰色角标 ROI 内。具体按键逻辑以 RTL 控制模块及 docs 为准。

## 算法与适用范围

最终边缘经 4×4 OR 汇聚，保留细边；有界搜索最多 8 个符合尺寸的候选，验证四边支持、角点或曲线一致性后，最终只输出一个有效目标。未实现同时标注多个目标。

圆/椭圆量化包围框下限约 48×48 像素，矩形约 32×32，实际建议明显大于下限。矩形以接近水平/竖直为主，椭圆以坐标轴近似对齐为主。强透视、大角度旋转、严重遮挡、密集粘连纹理不保证识别；不确定时输出 NONE。

结果在帧边界更新，约一帧滞后，具有 4 像素级量化；快速移动时着色可能滞后。HUD 诊断数字和 W/H 沿用十六进制，尺寸不是毫米。

## 原交付验证记录

本次仅整理文件，未重新执行完整 FPGA 编译，也未新增实板验收结论。

原 G2 记录包括 50 帧几何及反例测试，覆盖圆、横纵椭圆、矩形、粗描边、空白、三角形和圆弧；另有 RGB 到最终识别集成、实际轮廓着色、原模式回归、帧同步及异常恢复检查。Efinity map/interface/pnr/pgm 完成。

| 项目 | 原交付报告 |
| --- | --- |
| XLR | 48041 / 60800（79.01%） |
| RAM | 211 / 256（82.42%） |
| DSP | 23 / 160（14.38%） |
| 最小 setup | +0.169 ns |
| 最小 hold | +0.026 ns |
| HDMI 像素域 setup | +0.181 ns |

详见 `reports/V11_G2_VALIDATION.md`、`reports/g2_release_manifest.json`。这些记录不能替代真实物体准确率、长期稳定性及实板验收。

## 测试与重新构建

从工程根目录执行，需要 Python 与 Icarus Verilog。可用 IVERILOG、VVP 环境变量指定可执行文件；Windows 便携版本可通过 `RTL_SIM=icarus_direct` 使用 `scripts/icarus_direct.py`。

```powershell
python scripts/verify_g2_shapes.py
python scripts/verify_g2_negatives.py
python scripts/verify_g1r_integration.py
```

部分脚本沿用 G1R 命名，仅表示复用测试框架。`scripts/build_g2.ps1` 保留原作者 Efinity 与 EFXPT_HOME 绝对路径，换电脑前需要调整，或直接用 Efinity GUI 构建。

`publish_g2.py` 是原本地发布核验流程，依赖相邻历史工程及构建产物，不是独立克隆后即可使用的一键构建命令。报告中的绝对路径属于原验证环境，不是可移植配置。`START_HERE_G2.md` 保留原交付说明，路径以当前仓库为准。

## 上传与权利说明

保留源码、IP、约束、初始化文件、测试、最终固件及验证报告；排除编译工作目录、仿真可执行产物和波形。没有创建或上传 GitHub 仓库。

保留厂商示例、IP 和部分加密源文件的原声明。参见 `NOTICE.txt` 及各文件版权说明；本整理不为第三方文件额外授予再分发权，也未对整个工程添加统一开源许可。
