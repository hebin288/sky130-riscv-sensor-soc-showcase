# Die 形状与封装说明

本项目两种交付形式的版图均非正方形，这是正常且有意为之的结果——**die 不需要是方形**，封装对长宽比没有硬性要求（DRAM、射频芯片大多为长条形）。封装只看两件事：焊盘环能否打线、die 能否放进封装腔体。

## 1. 为什么不是正方形

| 版图 | 尺寸 | 形状成因 |
|---|---|---|
| `chip_top`（独立裸片） | 3800 × 2016 µm，约 1.9 : 1 | **pad-limited**：42 个 `sky130_ef_io` 环上单元沿周长排布，pad 高约 198 µm；核心区需容纳 4×2 SRAM 宏阵列（约 3032 µm 宽）+ 底部逻辑带。宽度被焊盘排布决定，高度由宏阵列决定。 |
| `openframe_project_wrapper` | 3166 × 4766 µm，约 1 : 1.5 | **模板固定**：OpenFrame harness 的 user area 尺寸由框架写死，不可更改——形状由类 Caravel 母片的用户槽位决定。 |
| `litex_chip_top`（LiteX 验证片） | 3600 × 1900 µm | 同 chip_top 原理：4 信号 + 8 电源焊盘环 + 4×2 SRAM 阵列决定的矩形。 |

## 2. 将来的封装路径

### 独立裸片 `chip_top` / `litex_chip_top`

| 方案 | 说明 |
|---|---|
| **QFN-48 / QFN-64 打线封装** | 环上焊盘均为标准可打线 pad；矩形 die 在 QFN-64（典型 9×9 mm 体）腔体内轻松放下——最直接的出货形态 |
| **COB（chip-on-board）** | 裸片直接邦定到 PCB，低成本传感器节点常见路线 |
| **WLCSP（倒装植球）** | 需重做顶层：当前 `gpiov2` 是打线型 pad，不是 bump pad，要 WLCSP 得换 bump 单元 + RDL 重布线层 |

### OpenFrame wrapper

它**不是独立封装对象**——嵌入 OpenFrame harness（类 Caravel 母片），由 shuttle 项目（如 chipIgnite）整片流片并封装交付。Efabless 历史 MPW 出货形态为 **QFN-64 封装 + 评估板**。

## 3. 如果想改成正方形

技术上可做（减少焊盘数、宏阵列改 2×4 竖排），但**对方形没有封装收益**——只会让 pad pitch 变松或 die 变小，属美学改动而非工程需求。当前不计划为此调整版图。
