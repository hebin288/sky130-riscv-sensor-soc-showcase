# Precheck 说明

## 一、 Precheck 一般用于什么检测？

在开源/商业 MPW（多项目晶圆，如 ChipFoundry、Efabless、Google MPW）流程中，**Precheck 是官方的"流片前置自动化合规性准入网关（Submission Gatekeeper）"**。

它的核心目的不是验证你的芯片功能对不对（CPU 能不能跑代码），而是验证**"你的设计会不会破坏晶圆厂的制造设备、会不会与共享晶圆的其他用户发生冲突、是否能安全接入官方的框架与焊盘环"**。

具体检测内容分为三大类：

### 1. 制造安全与工艺合规性（基于 KLayout）

这是最关键的物理准入，直接关系到光刻与刻蚀良率：

- **`klayout_feol` / `klayout_beol`**：前道（晶体管/扩散区/多晶硅）与后道（金属层/通孔）的设计规则检查（DRC）。
- **`klayout_offgrid`**：格点检查，确认所有多边形顶点均落在制造网格（sky130 为 5 nm）上，防止光刻机解析错误。
- **`klayout_zeroarea`**：零面积奇异图形检查（防止数据解析异常）。
- **`klayout_met_min_ca_density`**：金属与接触孔最小密度检查（防止化学机械抛光 CMP 时过度研磨凹陷）。
- **`spike_check`**：尖角/细丝多边形检查（防止微细结构在刻蚀时剥落或短路）。
- **`metalcheck`**：非法金属层检查，防止调用了未授权或保留的特殊层。

### 2. 官方框架互联与模板合规性（Template Integrity）

保证用户的版图能严丝合缝地放进芯片焊盘环：

- **`topcell_check`**：顶层宏名字必须是规范的 `openframe_project_wrapper`，die 边界尺寸必须严格等于规范尺寸（3166.63 × 4766.63 µm）。
- **`xor`**：将用户的 GDS 与官方空模板 GDS 进行布尔异或比对，**确保用户没有篡改或破坏官方预置的保留区域**（例如东边界电源探针引脚、边界基准等）。
- **`illegal_cellname_check`**：单元命名检查，防止用户内部单元名与官方库/PDK 保留宏重名造成冲突。

### 3. 电学安全与引脚状态（LVS & CVC/OEB）

防止上电瞬间损坏芯片：

- **`oeb`（CVC，Circuit Validation Check）**：检查所有 GPIO 引脚的方向与输出使能（OEB）。确保芯片复位与上电时，IO 不会处于未定义态而与板级总线发生"争用短路（bus contention）"。
- **`pdnmulti`**：多电源域隔离检查，确认各电压域（1.8V、3.3V）未发生意外短路。
- **`lvs`**：电路网表与版图比对，验证逻辑连通性。

---

## 二、 可以用于裸 Die（Bare Die）的检测吗？

**结论取决于"裸 Die"指的是哪一种形式：**

### 1. 形式 A：自带完整焊盘环的自立式独立裸芯片（如本项目的 `chip_r7`）

👉 **不能直接跑 `cf precheck` 命令，但它底层的核心规则脚本可以直接用于裸 Die 检测。**

- **为什么不能直接运行命令**：
  `cf-precheck` 命令行工具是深度绑定在 Caravel / OpenFrame 平台规范下的，它强制要求顶层必须叫 `openframe_project_wrapper`，并会强制执行 `xor`（与官方框架比对）、`topcell_check`、OpenFrame 的 GPIO 检查等。独立芯片（`chip_top`）没有这些包裹层，直接运行命令会在第一步就因"缺少模板"而报错。
- **如何用于裸 Die**：
  `cf-precheck` 内部调用的核心检查内核——**KLayout sky130A DRC 脚本（`sky130A_mr.drc`）、Netgen LVS、以及 offgrid/zeroarea 脚本**，本质上就是晶圆厂交付裸 Die（如提交给 wafer.space 或 MOSIS 单独流片）的标准 Signoff 工具。我们在 `chip_r7` 阶段执行的 Netgen LVS 0 差异、KLayout DRC 31 处（全部为 `ef_io` 焊盘单元内部厂商掩膜图形，IP 固有豁免），正是这种纯裸 Die 级别的检测。

### 2. 形式 B：未带 Pad Ring 的内部逻辑宏（如纯数字核 `soc_of_logic`）

👉 **不能。**
像 `soc_of_logic` 这种只有内部走线、没有外圈引脚定义或保护环的中间宏，Precheck 无法对它单独定界（它没有完整的框架边界与电源入口），必须放在外层 wrapper 或整芯片中一起检测。

### 3. 形式 C：OpenFrame 框架最终交付的"无封装裸片"（Bare Die Delivery）

👉 **完全适用，且正是为其量身定制的。**
很多高校和初创团队在芯片流片时选择的是"Bare Die（未封装晶圆裸划片，直接用金线打线或倒装）"交付方式。OpenFrame 的整套 GDS 就是送往 SkyWater 晶圆厂做掩模的裸芯片版图。因此，**`cf-precheck` 全部检查项通过（或对 FAIL 项完成 cell 级归属归档并获得提交方豁免认可），即满足 OpenFrame 裸 Die 提交的物理准入要求**。

---

## 三、 本项目 OpenFrame Wrapper（soc_of_w10）的 Precheck 最终结果

| 检查项 | 状态 | 说明 |
|---|---|---|
| Top Cell | PASS | 顶层命名与 die 边界合规 |
| Spike Check | PASS | 无尖角/细丝图形 |
| Illegal Cellname | PASS | 命名空间合规 |
| KLayout Offgrid | PASS | 全部图形落在制造网格 |
| KLayout Pin Label | PASS | 引脚标签与图形对齐 |
| KLayout ZeroArea | PASS | 无零面积图形 |
| OEB (CVC) | PASS | 0 error，14 条良性 warning；44 个 GPIO 配置全部正确识别 |
| XOR | PASS | `Total XOR differences: 0`，与官方 golden 模板零差异 |
| LVS (Netgen) | PASS | `Circuits match uniquely`，0 pin mismatch |
| KLayout FEOL | FAIL → IP 豁免 | 3 处 `MR_licon.SP.6`，全部位于 OpenRAM SRAM bitcell 内部 |
| KLayout BEOL | FAIL → IP 豁免 | 264 处 `MR_mcon.CON.10`，全部位于 OpenRAM SRAM 内部 |
| KLayout 密度 | FAIL → IP 豁免 | 204 处 `li1.pd.1d`，约 200 处 SRAM 内部 + 4 处 cell 边界汇总条目 |
| Magic DRC | SKIP | 官方默认关闭 |

### LibreLane 尾日志中三项 deferred 错误的最终定性

- **Magic DRC ~4461 万条**：Precheck 默认不测 Magic DRC（`--magic-drc` 需手动开启）。该计数 100% 来自 SRAM 宏内部专有规则的已知误报；LibreLane 抽象层 KLayout 为 0，官方全展平 KLayout 的 471 处违例经 cell 级归属分析，其中 467 处定位于 SRAM 硬宏内部，4 处为密度检查的 cell 边界汇总条目。
- **Magic Illegal Overlap 27 处**：Precheck 无此检查项；实测全部位于 die 东边界 `vccd1_connection`/`vssd1_connection` 宏的 LEF 抽象 OBS 与 met3 电源探针搭接处，属模板固有特征。
- **LibreLane 内部 LVS 2 处端口错误**：器件/网络差异均为 0，仅边界 `vccd1`/`vssd1` 探针引脚因连接宏 LEF 无引脚而悬空。在官方 precheck 中通过 `LVS_FLATTEN` 扁平化连接宏后该伪影自动消失，最终取得 `Circuits match uniquely`；KLayout GDS 物理追踪亦实证探针与内部电网完全连通（119 条 met5 + 3.4 万 met4 图形，vccd1/vssd1 无短路）。
