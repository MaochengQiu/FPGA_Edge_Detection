# G1R 几何仿真最终结果

状态：PASS；没有实板验收。

最终 RTL SHA256：`33e92bb1c5bef51273ee8b29938cfba44a4246388d7275e14fa917d3f2f495cf`。

全部九组测试使用记录的最终源码/测试台哈希；旧 G1 的三个拒绝反例在冻结参考实现上实际复现。

| 组别 | 结果 |
|---|---|
| baseline | PASS |
| small | PASS |
| hd | PASS |
| timeout | PASS |
| deadline | PASS |
| reset | PASS |
| startup | PASS |
| boundary | PASS |
| circles | PASS |

包含 36 帧通用图形、10 帧真实 1920×1080 栅格、复位/截止/首次同步、17 帧边界反例，以及 80 帧圆形尺寸和横纵相位检查。小圆保持 NONE，正常尺度圆形保持 CIRCLE；小圆误报 SQUARE 的旧结果已修正并复跑。

更完整的最终源码/固件、资源、时序与验证结论见 [最终验证报告](../../reports/V11_G1R_VALIDATION.md)。
原始逐帧输出和哈希见 [汇总 JSON](work/verification_summary.json)。
