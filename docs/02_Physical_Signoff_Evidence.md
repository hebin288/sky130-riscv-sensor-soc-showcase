# 02 — 双形态物理后端实现与官方 Precheck 签核证据包

**目标工艺**：SkyWater SKY130A (130nm 1P5M CMOS)
**工具链版本**：LibreLane (OpenROAD + Yosys 0.67 + slang) | CF Precheck v1.3.7 | KLayout v0.30.9 | Magic v8.3.678 | Netgen
**交付形态**：
1. **形态 A（MPW Shuttle 形态）**：`openframe_project_wrapper`（适配 ChipFoundry chipIgnite OpenFrame 模板，3166.63 × 4766.63 µm）
2. **形态 B（自立式裸片形态）**：`chip_top` / `chip_r7_eco`（带完整 34-GPIO + 8-Power 自建焊盘环，3800 × 2016 µm）

---

## 一、 双形态核心物理签核指标总览

| 签核维度 | 形态 A：OpenFrame Wrapper (`soc_of_w10`) | 形态 B：自立式裸片 (`chip_r7_eco`) | 签核状态 |
|---|---|---|---|
| **Die 尺寸 / 面积** | 3166.63 × 4766.63 µm (**15.09 mm²**) | 3800.0 × 2016.0 µm (**7.66 mm²**) | PASS |
| **架构与宏布局** | 独立硬化逻辑宏 `soc_of_logic` (2400×1000 µm, met1–4) + 顶层外置 8×2KB SRAM (met4/met5 PDN 直连) | 顶层集成 34×`gpiov2_pad` + 8×电源焊盘 + 8×2KB SRAM 硬宏 | PASS |
| **详细布线 DRC (`route__drc_errors`)** | **0**（6 轮迭代收敛） | **0**（17 轮迭代收敛） | **PASS** |
| **LVS 器件/网络/引脚差异** | **0 / 0 / 0** (`Circuits match uniquely`) | **0 / 0 / 0** (`Circuits match uniquely`) | **PASS** |
| **GDS 模板布尔异或 (XOR)** | **0 差异**（对比官方 golden 模板） | **0 差异**（DEF ↔ GDS 一致） | **PASS** |
| **CVC / OEB 电学规则检查** | **0 Error**（44 个 GPIO 模式全部正确识别） | N/A（自建 Pad-ring） | **PASS** |
| **Setup / Hold 时序违例 (`tt` 三角)** | **0 / 0**（16 MHz 主频，Hold 余量充足） | **0 / 0**（含片外 IO 延迟约束） | **PASS** |
| **电源网络 (PDN) 连通性** | **0 违例**（`vccd1`/`vssd1` 探针物理连通全部 119 条 met5） | **0 开路**（8 块 SRAM 共 64 个电源引脚 100% 搭接，IR Drop 最差仅 13.5 µV） | **PASS** |
| **天线效应 (Antenna)** | 逻辑宏 **0 违例**（440 端口保护二极管）；顶层 256 根 SRAM 输出线 **0 违例** | **0 违例网**（全芯片插入 2161 个天线保护二极管） | **PASS** |

---

## 二、 关键工程难题攻克记录（Engineering Case Studies）

在开源 EDA 流程中集成多块 OpenRAM SRAM 硬宏与整芯片焊盘环时，存在大量教科书未记载的工程陷阱。本基线已形成标准化解决方案：

### 2.1 难题一：8 块 SRAM 硬宏的 met4 电源引脚与宏内层数限制冲突
* **现象**：OpenFrame 规范要求子宏内部布线限制在 `met1–met4`（保留 `met5` 给顶层电源跨接），但 `sky130_sram_2kbyte` 的电源引脚位于 `met4` 环上，需要 `met5` 条带通过 `via4` 向下打孔供电。若将 SRAM 包在逻辑子宏内并限制 `RT_MAX_LAYER=met4`，PSM 电源检查会直接报 SRAM `vccd1` 开路。
* **解决方案（SRAM 外置分层硬化架构）**：
  1. 将纯数字逻辑拆分为 `soc_of_logic`（2400 × 1000 µm），仅用 `met1–met4` 独立硬化，并在全部输入端口自动插入 440 个天线保护二极管（实现逻辑宏自身 DRC/LVS/Antenna 全部清零）；
  2. 将 8 块 SRAM 直接摆放在 `openframe_project_wrapper` 顶层，利用顶层 `met4 + met5` 双层电源网格直接贯通供电，并用 KLayout `LayoutToNetlist` 编写物理追踪脚本验证 119 条 `met5` 电源条带与东侧 `vccd1_connection` / `vssd1_connection` 探针 100% 物理导通。

### 2.2 难题二：官方 `cf-precheck` LVS 的边界电源连接片伪影消除
* **现象**：OpenFrame 顶层的 `vccd1_connection` 与 `vssd1_connection` 是用于桥接探针与核心电网的纯金属连接宏。若按默认黑盒抽象抽取，Netgen LVS 会报顶层电源引脚不匹配。
* **解决方案**：在 `lvs_config.json` 中对两个连接宏启用 `LVS_FLATTEN` 扁平化展开，同时对 8 块 SRAM 启用 `EXTRACT_ABSTRACT` 抽象比对，最终在官方 Precheck LVS 中实现 **`Circuits match uniquely`（零引脚不匹配、零器件差异）**。

### 2.3 难题三：跨宏边界的 Hold 时序收敛与天线修复
* **现象**：子宏独立硬化时假设了 `-min 0.5ns` 输入延迟，而顶层 Wrapper 在默认 `0ns` 外部延迟下复核时出现 4 条跨宏边界 Hold 违例；同时 OpenROAD 在 Wrapper 边界引脚自动插二极管时因超出 Die 区域崩溃。
* **解决方案**：将端口天线二极管前移至子宏 `soc_of_logic` 级完成，并在顶层 SDC 与子宏边界统一最小路径延迟模型，彻底消除 Hold 违例与工具崩溃。

---

## 三、 官方 ChipFoundry Precheck 13 项逐项核验清单

**GDS SHA-1 签名**：`ee577a3197a036802df1050906bae88534a36450`

| # | 官方检查项 | 结果 | 证据说明 |
|---|---|---|---|
| 1 | `topcell_check` | **PASS** | 顶层单元名 `openframe_project_wrapper` 严格合规 |
| 2 | `klayout_offgrid` | **PASS** | 0 违例（全部图形严格对齐 5 nm 制造网格） |
| 3 | `klayout_pin_label_purposes_overlapping_drawing` | **PASS** | 0 违例 |
| 4 | `klayout_zeroarea` | **PASS** | 0 零面积碎屑图形 |
| 5 | `spike_check` | **PASS** | 0 锐角/尖刺图形 |
| 6 | `illegal_cellname_check` | **PASS** | 单元命名空间 100% 合规 |
| 7 | **`xor`** | **PASS** | **`Total XOR differences: 0`**（与官方 `openframe_project_wrapper_empty.gds` 模板外框零差异） |
| 8 | **`oeb` (CVC 电学规则)** | **PASS** | **0 Error**：全部短路、正偏二极管、栅源过压检查均为 0；44 个 GPIO 配置全部正确识别 |
| 9 | **`lvs` (Netgen)** | **PASS** | **`Circuits match uniquely.`** 零器件差异、零网络差异、零引脚不匹配 |
| 10 | `klayout_feol` | Waiver (IP 内部) | 3 处 `MR_licon.SP.6`，**100% 位于 OpenRAM SRAM bitcell 内部**，用户设计区 0 违例 |
| 11 | `klayout_beol` | Waiver (IP 内部) | 264 处 `MR_mcon.CON.10`，**100% 位于 OpenRAM SRAM replica/bitcell 内部**，用户布线区 0 违例 |
| 12 | `klayout_met_min_ca_density` | Waiver (IP 内部) | 200 处位于 SRAM 内部子单元 + 4 处 cell 边界汇总窗口（用户标准单元区已填充 decap/fill） |
| 13 | `magic_drc` | SKIP | 官方 Precheck 默认跳过 |

---

## 四、 全 GDS 展平 DRC 的 Cell 级归属剥离证明（Waiver 依据）

由于官方 `sky130A_mr.drc` 对全芯片 GDS 进行展平扫描，会深入 `sky130_sram_2kbyte_1rw1r_32x512_8` 硬宏内部。通过对三份官方 XML 报告进行自动化脚本解析，证明 **用户自有逻辑宏与顶层布线实现 0 真实 DRC 违例**：

1. **FEOL (`klayout_feol_check.xml`)**：共 3 处 `MR_licon.SP.6`
   - `sky130_fd_bd_sram__openram_dp_cell` × 1
   - `sky130_fd_bd_sram__openram_dp_cell_replica` × 1
   - `sky130_fd_bd_sram__openram_dp_cell_dummy` × 1
   - **结论**：Foundry 提供的 SRAM 专用紧凑 bitcell 规则与通用数字规则的固有差异，属标准硬化 IP 豁免项。
2. **BEOL (`klayout_beol_check.xml`)**：共 264 处 `MR_mcon.CON.10`
   - 256 处位于 8 块 SRAM 的 `replica_column` / `replica_column_0`（每块 32 处 × 8 = 256）；
   - 8 处位于 SRAM `dp_cell` / `replica` / `dummy`；
   - **结论**：用户逻辑与 Wrapper 互连区域 **0 违例**。
3. **局部互连密度 (`klayout_met_min_ca_density_check.xml`)**：
   - 200 处位于 SRAM 内部定制单元（`sense_amp`、`precharge`、`pdriver` 等）；
   - 4 处为窗口按 Cell 边界汇总条目（含纯 `met3+via3`、本身不含 `li1` 层的电源桥接宏 `vccd1_connection` / `vssd1_connection`）。
