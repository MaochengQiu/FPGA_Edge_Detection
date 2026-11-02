# V2：弱纹理 / 近距离细节增强（不修改任何板级配置）

## 依据与目标

依据你发来的新上板图：原版能抓到吸管、杯盖、书本大字和强反差电路图，但杯身浅纹、人脸五官及暗部细节不连续。上侧/左侧特征更好也可能与局部光照、镜头景深、曝光、焦点有关；标准 Sobel 卷积核在数学上是方向对称的，不能仅凭屏摄照片判定是某一方向的卷积错误。

本次保留上一版左右完整视野对照显示、Sobel 内核、同步接口、分辨率、DMA/DDR、所有 Efinity IP/顶层/管脚。不声称光学失焦的细节能通过数字算法完全恢复。

## 具体 RTL 改动

| 文件 | 修改 |
|---|---|
| `rtl/edge/preprocess/img_preprocess.sv` | 在已有灰度 3×3 窗口引入前处理模式3，3×3 Gaussian 的同时实现 `clip(3*C-2*G)`；直接使用加法/移位与饱和选择，保持前处理 **9拍** 延迟、帧对齐控制、接口不变。其它0直通/1中值/2Gaussian 保留。|
| `rtl/edge/control/img_control.sv` | 默认阈值 `64→40`、前处理 `0→3`；四种模式循环，host cfg可写3，阈值步进仍是8。帧边界更新机制保持不变。|
| `sim/tb_control.sv` | 更新四模式循环与默认值检查。|
| `scripts/run_tests.py` | 添加模式3数学期望，并把流水线仿真覆盖四个模式。|
| `scripts/check_detail_reference.py` | 标准库纯 Python 数学穷举与软纹理样例：**不是 RTL 仿真**。|

公式：`G = (P00+2P01+P02+2P10+4P11+2P12+P20+2P21+P22+8) >> 4`；`S=clip(3P11−2G,0,255)`。输入/输出均为8bit；内部 signed 12bit 足够容纳 `−510..765`，不发生有符号溢出。Gray 的延迟、Sobel 4级、边缘二值化1级和合成1级保持不变，整体 `2*HTOTAL+22` 拍，时序无调整。

## 直接上板建议

默认阈值40+细节增强。对着 **同一杯子**，确保在相机合焦距离内，室内均匀补光，固定物距再比较（不要一边移动一边比）。右侧线条若偏少：KEY2 一次→32，再一次→24。若纹路已经出现但满屏散点：KEY1→48/56；或长按 KEY3 切 0直通、1中值、2高斯，在各模式比较。显示模式按 KEY3 短按切换，默认3左右完整视野对比。

用两个样本排除光学问题：A. 印在纸上的 1mm 黑白棋盘格（高对比、细间距）；B. 杯子上浅灰细纹（低对比）。如果A在近距离也明显糊成一片，优先检查相机对焦/物距/快门/照明，FPGA不能创造摄像头没有采集到的空间频率信息。

## 验证边界

可运行：`python3 scripts/check_project.py`、`python3 scripts/test_project_structure.py`、`python3 scripts/check_detail_reference.py`。安装 Icarus 后：`python3 scripts/run_tests.py`。在本机 Efinity 完成 Design Check/Synthesis/Place & Route/Timing/bitstream，上传实板照片或首个综合错误继续迭代。**没有调用 Efinity，也没有实板和镜头实时视频样本，未验证板上效果。**
