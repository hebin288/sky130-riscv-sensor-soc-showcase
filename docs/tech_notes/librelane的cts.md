# LibreLane 中的 CTS

## 结论

LibreLane 里**只有一种** CTS 引擎——**TritonCTS**（OpenROAD 内置，通过 `clock_tree_synthesis` 命令调用）。它既不是 H-tree 也不是 mesh/fishbone，而是**基于 sink clustering 的自底向上缓冲时钟树**。H-tree、mesh、fishbone 在 LibreLane/OpenROAD 中均没有对应实现或选项。

---

## 一、 实际调用的引擎与算法

`scripts/openroad/cts.tcl` 的核心是 `clock_tree_synthesis`，算法骨架：

1. **sink clustering**（自底向上聚类）：把所有触发器的时钟 pin 按几何位置递归聚类成簇（受 `CTS_SINK_CLUSTERING_SIZE` / `_MAX_DIAMETER` 控制簇的大小和直径上限）；
2. **逐级插 buffer**：每个簇用一个 clock buffer 驱动，簇间再向上聚类，直到收敛到时钟根——生成**非对称但 skew 受控的缓冲树**；
3. **约束驱动**：用 `CTS_MAX_CAP`/`CTS_MAX_SLEW` 做特征化，保证每级 buffer 的负载和边沿达标；`CTS_BALANCE_LEVELS` 强制各分支级数对齐以降低 skew。

它最接近教科书里的"**缓冲时钟树 + 聚类平衡（bounded-skew buffered tree）**"，不是预定义几何结构。

## 二、 三种经典结构为何都不适用

| 结构 | 本质 | 在 LibreLane/OpenROAD |
|---|---|---|
| **H-tree** | 固定对称递归分形，天然零 skew 但 rigid | 无此模式——属手工 floorplan 结构 |
| **Mesh** | 末端网格短接全部 sink，top 树驱动网格 | 无——仅超高频 CPU 使用，skew 极小但功耗/布线代价大 |
| **Fishbone** | 主干+梳齿结构，少 buffer 减 skew | 无——研究型拓扑，开源工具链未实现 |

TritonCTS 输出从几何上有点像"非对称 H-tree"（聚类会递归切分区域），但本质区别是：**H-tree 先定几何再挂 sink，TritonCTS 先聚类 sink 再长树**。

## 三、 LibreLane 暴露的 CTS 可调参数

`steps/openroad.py` 中 `CTS` 类导出的完整配置项：

| 参数 | 作用 |
|---|---|
| `CTS_CLK_BUFFERS` / `CTS_ROOT_BUFFER` | 允许使用的 buffer 类型（如 sky130 `clkbuf_*`） |
| `CTS_MAX_CAP` / `CTS_MAX_SLEW` | 特征化约束（pF / ns） |
| `CTS_SINK_CLUSTERING_ENABLE` / `_SIZE` / `_MAX_DIAMETER` | sink 聚类控制 |
| `CTS_MACRO_CLUSTERING_SIZE` / `_MAX_DIAMETER` | 宏聚类控制 |
| `CTS_BALANCE_LEVELS` | 强制分支级数对齐 |
| `CTS_DISTANCE_BETWEEN_BUFFERS` | buffer 间距上限 |
| `CTS_CLK_MAX_WIRE_LENGTH` | 时钟根到树的线长上限（之后 `repair_clock_nets`） |
| `CTS_OBSTRUCTION_AWARE` | 绕障碍布线 |
| `CTS_APPLY_NDR` | 时钟网套非默认布线规则（双倍宽距） |
| `CTS_DISABLE_POST_PROCESSING` | 关闭 outlier sink 后处理 |
| `CTS_CORNERS` | 表征工艺角 |
| `CTS_SINK_BUFFER_MAX_CAP_DERATE_PCT` / `CTS_DELAY_BUFFER_DERATE_PCT` | 降额系数 |
| `CLOCK_NET` | 指定哪根网做 CTS |

## 四、 若确实需要 H-tree/mesh 的现实路径

- **RTL/DEF 手工预置**：在网表里手工例化对称 buffer 树/网格，给这些 cell 打 `FIXED`/`PLACED` 坐标，时钟网标 `dont_touch`，再用 `CLOCK_NET` 让自动 CTS 跳过；
- **外部生成后读入**：用专门脚本生成 H-tree 的 DEF/Verilog 片段，作为"宏"插入；
- 对绝大多数 130nm 设计（包括本项目 16 MHz）**没有必要**——TritonCTS 聚类树在低频下 skew 余量已足够大（本项目 CTS 后 hold slack +1.15ns 即证据）。

---

## 五、 附：Clock Skew 的准确含义

Clock skew 的准确定义是：**同一时钟源到达两个不同触发器时钟引脚的时间差**。

### 1. 定义

```
skew(A,B) = t_arrive(clk→FF_A) − t_arrive(clk→FF_B)
```

- **Local skew**：只在"有数据路径相连的一对触发器"（launch FF → capture FF）之间讨论——直接影响 setup/hold；
- **Global skew**：全芯片所有时钟 sink 中，**最大到达时间 − 最小到达时间**。

### 2. 与相关概念的区别

| 概念 | 含义 | 与 skew 的关系 |
|---|---|---|
| **Insertion delay（插入延迟）** | 时钟从源点到**某一个** sink 的绝对延迟 | skew ≠ 延迟本身；两个 sink 各 10ns 延迟但相同 → skew = 0 |
| **Latency** | source latency + network latency | 同上 |
| **Jitter** | 同一 sink 上时钟沿的**时间抖动** | 统计量，不是位置差 |
| **Skew** | 不同 sink 之间到达时间的**空间差** | 由时钟树拓扑/路径不匹配产生 |

关键点：**skew 看的是"差"不是"大"**——时钟到达得晚没关系，只要大家一起晚。CTS 的目标不是最小化延迟，而是最小化 sink 间的延迟**差**。

### 3. 对 setup/hold 的实际作用

- **Setup**：`capture 沿延迟 > launch 沿延迟` 的正 skew 是**有利**的（capture 沿来得晚，等效周期变长）；反之为负 skew；
- **Hold**：正 skew **有害**——launch 数据"追"上 capture 沿更早，hold 余量变小。这也是 hold 检查用 min 路径、把 skew 算得最悲观的原因；
- 本项目 `set_propagated_clock` 之后，skew 是**实测**的时钟树 buffer 延迟差——CTS 后报告里的 skew 就是各 sink 实测延迟的极差。

### 4. 对本项目

16 MHz + TritonCTS 聚类树：周期 62.5ns 远大于实际 skew（通常几十~几百 ps），skew 对 setup 几乎无影响，但它是 hold 余量的一部分（hold slack +1.15ns 足够覆盖）。

---

**一句话**：LibreLane/OpenROAD 的 CTS 只有 TritonCTS 一种（sink-clustering 缓冲树）；H-tree/mesh/fishbone 均需手工预置并脱离自动 CTS。Clock skew 则是同一时钟沿到达不同触发器的时间差——差值而非延迟本身。
