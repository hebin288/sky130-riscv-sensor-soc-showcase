# SKY130A RISC-V 低功耗传感器与边缘控制 SoC 物理实现基线

> **全开源工具链 RTL-to-GDSII 闭环 | 双形态物理签核完备 | ChipFoundry 官方 Precheck 验证通过**

本仓库展示了面向**定制传感器接口（AFE）、工业边缘控制与高校科研实验载荷**的 32 位 RISC-V (`RV32IMC`) 低功耗 SoC 物理实现基线。项目基于 SkyWater **SKY130A (130nm CMOS)** 工艺，使用 100% 开源 EDA 工具链（Yosys + slang + LibreLane/OpenROAD + KLayout + Magic + Netgen + CVC）完成从 SystemVerilog RTL 到最终 GDSII 的全流程实现与签核验证。

---

## 一、 双形态芯片版图展示 (Silicon Layouts)

本基线同时支持 **MPW 拼板流片（ChipFoundry OpenFrame）** 与 **自立式商业裸片（Standalone Pad-ring）** 两种物理交付形态：

| 形态 A：OpenFrame Shuttle 顶层 (`3166 × 4766 µm`) | 形态 B：Standalone 自建焊盘环裸片 (`3800 × 2016 µm`) |
| :---: | :---: |
| ![OpenFrame Full Layout](assets/openframe_full.png) | ![Standalone Chip Layout](assets/chip_r7_eco_full.png) |
| **15.09 mm²** \| 硬化逻辑宏 + 8×2KB 外置 SRAM + 44 GPIO | **7.66 mm²** \| 34×`gpiov2` 焊盘 + 8×电源焊盘 + 8×2KB SRAM |

| 独立硬化核心逻辑宏 `soc_of_logic` (`2400 × 1000 µm`) | SRAM 宏与顶层 `met4/met5` 电源网格跨接特写 |
| :---: | :---: |
| ![Logic Macro Layout](assets/soc_of_logic_macro.png) | ![SRAM PDN Zoom](assets/sram_pdn_zoom.png) |
| `met1–met4` 独立收敛 \| 440 端口天线保护二极管 \| 0 DRC / 0 LVS | 解决硬宏 `met4` 电源环与子宏布线层限制冲突，119 条 `met5` 贯通 |

---

## 二、 核心签核成绩单 (Signoff Metrics Summary)

| 签核检查项 | OpenFrame (`soc_of_w10`) | Standalone (`chip_r7_eco`) | 官方口径结论 |
|---|---|---|---|
| **CPU 与存储架构** | Ibex RV32IMC + 4KB ROM + 16KB SRAM (8×2KB) | Ibex RV32IMC + 4KB ROM + 16KB SRAM (8×2KB) | 功能全集一致 |
| **详细布线 DRC (`route__drc_errors`)** | **0**（6 轮收敛） | **0**（17 轮收敛） | **PASS** |
| **官方 Netgen LVS** | **`Circuits match uniquely`** (0 mismatch) | **`Circuits match uniquely`** (0 mismatch) | **PASS** |
| **GDS 模板布尔异或 (XOR)** | **`Total XOR differences: 0`** | **0 差异** | **PASS** |
| **CVC / OEB 电学规则** | **0 Error**（44 GPIO 模式全部正确识别） | N/A（自建 Pad-ring） | **PASS** |
| **几何规则 (Offgrid / Spike / Zeroarea)** | **全部 0 违例** | **全部 0 违例** | **PASS** |
| **Setup / Hold 时序 (`tt` 三角 @ 16 MHz)** | **0 / 0 违例** | **0 / 0 违例** | **PASS** |
| **电源网格 (PDN) 物理连通性** | **0 开路 / 0 短路**（KLayout 全网追踪验证） | **0 开路**（64 个 SRAM 电源脚 100% 搭接，IR Drop 13.5 µV） | **PASS** |
| **天线效应 (Antenna)** | 逻辑宏 **0 违例**；256 根 SRAM 输出线 **0 违例** | 全芯片 **0 违例网**（插 2161 个二极管） | **PASS** |

---

## 三、 技术优势与已攻克工程壁垒

1. **工业级低功耗与高可靠微架构**
   - **三异步时钟域严格隔离**：主时钟 `clk_i` (16 MHz)、常开域 `rtc_clk_i` (32.768 kHz) 与调试时钟 `jtag_tck_i` 通过专用 CDC 模块收敛；
   - **硬件安全深睡与多源唤醒**：PMU 自动检测总线与外设空闲后关断主时钟树（静态漏电地板约 `145 µW`），支持 **RTC 定时闹钟、UART1 RX 下降沿、JTAG Debug 强制唤醒**；
   - **全功能闭环验证**：配备 Verilator + C 固件的 T1（冷启动+全外设+深睡唤醒+看门狗复位恢复）、T2（NOR 损坏保护）、T3（JTAG 跨深睡在线调试）自动化回归套件。
2. **复杂多宏物理后端与 Precheck 通关能力**
   - 独创 **“逻辑宏 `met1–4` 独立硬化 + 8×SRAM 顶层外置 `met4/met5` PDN 直连”** 架构，彻底解决 OpenRAM 硬宏电源环打孔难题；
   - 解决 `vccd1_connection` / `vssd1_connection` 边界探针宏在官方 LVS 下的端口伪影，实现零引脚不匹配；
   - 建立全 GDS 展平 DRC 的自动化 Cell 归属剥离流程，精确证明用户逻辑与布线区 **0 违例**。

---

## 四、 仓库文档导航 (Documentation Index)

* **架构与签核核心文档**
  * 📄 [01 — RISC-V 传感器 SoC 架构规格书 (`docs/01_Architecture_Spec.md`)](docs/01_Architecture_Spec.md)
  * 📄 [02 — 双形态物理后端实现与官方 Precheck 签核证据包 (`docs/02_Physical_Signoff_Evidence.md`)](docs/02_Physical_Signoff_Evidence.md)
* **开源 EDA 物理设计深度专栏 (`docs/tech_notes/`)**
  * 📘 [ChipFoundry 官方 `cf-precheck` 检查机制与裸片适用性分析](docs/tech_notes/precheck说明.md)
  * 📘 [LibreLane / OpenROAD 时钟树综合 (TritonCTS) 原理与 Clock Skew 解析](docs/tech_notes/librelane的cts.md)
  * 📘 [LibreLane 静态时序分析 (OpenSTA) Slack 计算原理与多角签核口径](docs/tech_notes/slack计算原理.md)
* **RTL 代码规范示例 (`rtl_sample/`)**
  * 💻 [`apb_uart.sv` — 带深睡忙状态互锁与帧错误恢复的 APB UART 控制器](rtl_sample/apb_uart.sv)

---

## 五、 技术合作与商业服务 (Services & Collaboration)

我们面向**高校科研课题组、初创芯片团队与工业传感器厂商**提供高性价比的敏捷芯片实现服务：

1. **高校科研流片赋能（RISC-V SoC 测试载具服务）**
   - 您只需专注于核心创新模块（新型传感器 AFE、存算一体宏、AI/DSP 加速核、安全加密引擎），我们提供现成、已跑通物理签核的 RISC-V SoC 底座（含总线、BootROM、SRAM、JTAG 调试与外设），在 **4~8 周内** 完成集成并交付可投片的 SKY130 / GF180MCU GDSII 与测试固件，助力 ISSCC / JSSC / TCAS 论文流片实测。
2. **“底座换流片”联合 MPW 拼车计划**
   - 开放本 SoC 剩余逻辑面积与 AHB/APB 标准接口，诚邀有 MPW 流片计划的高校实验室或团队联合投片，共同分摊或由课题经费支持 Shuttle 费用，共享 100~1000 颗实测样片。
3. **OpenLane / LibreLane 物理后端代工与 Precheck 通关急救**
   - 承接 RTL-to-GDSII 物理实现外包，专项解决多宏 Floorplan、PDN 电源断路、天线效应违例、Hold 时序违例、Netgen LVS 不匹配及官方 `cf-precheck` 卡关问题。
4. **定制混合信号传感器 / 工业控制 ASIC 原型开发**
   - 从系统规格定义、RTL 设计、全链路仿真到 MPW 流片与样片 Bring-up 的一站式交钥匙工程。

---

### 📫 联系我们 (Contact)

* **商务与技术合作邮箱**：`hebin_21cn@foxmail.com`
* **微信 (WeChat)**：`BILLULM`
* *注：本公开仓库仅展示架构规格、示例模块与脱敏签核证据。完整 RTL 源码、物理实现配置脚本（`config.json` / `pdn.tcl` / `lvs_config.json`）及 GDSII 版图数据库面向商业合作与联合流片伙伴开放。*
