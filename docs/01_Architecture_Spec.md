# 01 — RISC-V 传感器与边缘控制 SoC 架构规格书 (`ibex_sensor_soc`)

## 1. 系统定位与架构概览

本平台是一套面向**定制传感器接口、工业微控制与科研实验载荷**的低功耗 32 位 RISC-V SoC 物理实现基线。基于 SKY130A 130nm 混合信号工艺，采用 100% 开源 EDA 工具链（Yosys + slang + LibreLane/OpenROAD + KLayout + Magic + Netgen）完成从 SystemVerilog RTL 到最终 GDSII 的全流程物理实现与官方 Precheck 签核。

```
+-----------------------------------------------------------------------------------+
|                              ibex_sensor_soc Top                                  |
|                                                                                   |
|  +------------------+     +------------------+     +---------------------------+  |
|  |  Ibex RV32IMC    |     |  RISC-V Debug    |     |  Boot ROM (4 KiB)         |  |
|  |  + Zicsr Core    |<--->|  Module (JTAG)   |     |  SPI NOR XIP/Shadow Boot  |  |
|  +--------+---------+     +--------+---------+     +-------------+-------------+  |
|           | I/D AHB-Lite           | SBA / Debug                 | AHB-Lite       |
|  +--------v------------------------v-----------------------------v-------------+  |
|  |                         32-bit AHB-Lite Interconnect                        |  |
|  +------------------+-----------------------------------+----------------------+  |
|                     |                                   |                         |
|           +---------v----------+              +---------v----------+              |
|           |  16 KiB On-Chip    |              |   AHB-to-APB       |              |
|           |  SRAM Controller   |              |   Bridge           |              |
|           |  (8 x 2KB Macros,  |              +---------+----------+              |
|           |   Per-Bank ICG)    |                        | APB                     |
|           +--------------------+       +----------------+----------------+        |
|                                        |                |                |        |
|  +-------------------------------------v----+  +--------v-------+  +-----v-----+  |
|  | Always-On (AON) & Power Management       |  | Sensor & Comm  |  | System    |  |
|  | - SYSCTRL / PMU (Deep-Sleep Clock Gate)  |  | - SPI0 (NOR)   |  | - 64b Tmr |  |
|  | - RTC (32.768 kHz Domain + Alarm Wakeup) |  | - I2C0 (Master)|  | - 16b GPIO|  |
|  | - WDT (AON Domain Hardware Watchdog)     |  | - UART0 / UART1|  |   + IRQ   |  |
|  +------------------------------------------+  +----------------+  +-----------+  |
+-----------------------------------------------------------------------------------+
```

---

## 2. 核心微架构特性

| 模块 | 规格说明 |
|---|---|
| **CPU 内核** | lowRISC Ibex (`RV32IMC_zicsr`)，2 级流水线，支持硬件乘除法与压缩指令集，向量化中断控制器 |
| **片上调试 (Debug)** | 兼容 RISC-V Debug Spec 0.13 (`riscv-dbg`)，支持四线 JTAG (`TCK/TMS/TDI/TDO`)、Program Buffer、Abstract Commands、System Bus Access (SBA) 以及跨深睡强制唤醒调试 |
| **存储子系统** | - **4 KiB Boot ROM**：上电自检并从外部 SPI NOR Flash (`0x51CE0ACE` 魔数校验) 搬移固件至 SRAM 执行<br>- **16 KiB SRAM**：由 8 块 `sky130_sram_2kbyte_1rw1r_32x512_8` 宏拼接，每块配备独立 `dlclkp_4` 门控时钟单元，仅被访问的 Bank 翻转以降低动态功耗 |
| **总线架构** | 32 位 AHB-Lite 主干矩阵（支持字节选通边带 `HBE`）+ 低速外设 APB 桥 |
| **外设集** | - **SPI0**：支持标准 SPI 主机通信及硬件自动轮询 Flash `WIP` (Write-In-Progress) 中断<br>- **I2C0**：支持标准/快速模式及从机时钟拉伸（Clock Stretching），已在仿真中闭环对接温湿度传感器 SHT3x 与 16 位 ADC ADS1115<br>- **UART0 / UART1**：支持 8N1、帧错误/溢出检测；UART1 支持深睡下 RX 低电平异步唤醒<br>- **GPIO**：16 位双向可配置 GPIO，支持边沿/电平中断触发<br>- **Timer**：64 位高精度系统定时器 (`mtime` / `mtimecmp`) |

---

## 3. 地址空间映射 (Memory Map)

| 起始地址 | 模块 | 功能说明与中断号 |
|---|---|---|
| `0x0001_0000` | **Boot ROM** | 4 KiB 掩膜启动 ROM（复位向量入口 `+0x80`） |
| `0x1A11_0000` | **Debug Module** | JTAG 在线调试模块（1 等待周期），产生 `debug_req` |
| `0x2000_0000` | **On-Chip SRAM** | 16 KiB 主存（8 × 2 KiB SKY130 硬宏，栈顶 `0x2000_3FF0`） |
| `0x4000_0000` | **SYSCTRL / PMU** | 复位原因 `RSTCAUSE`、跨复位保持寄存器 `SCRATCH`、`CHIPID (0x1BE50002)`、深睡控制 `PMU_CTRL` 与睡眠计数 `SLEEP_CNT` |
| `0x4000_1000` | **Timer** | 64 位定时器，触发 `irq_timer` (`mcause = 7`) |
| `0x4000_2000` | **WDT (AON)** | 常开域硬件看门狗（`rtc_clk` 驱动，使能后不可关闭，喂狗密钥 `0x5A5A5A5A`），超时触发全系统复位 |
| `0x4000_3000` | **GPIO** | 16 位通用 IO 控制与方向配置，触发 `fast[3]` (`mcause = 19`) |
| `0x4000_4000` | **I2C0** | I2C 主机控制器，触发 `fast[2]` (`mcause = 18`) |
| `0x4000_5000` | **UART0** | 主控制台串口，触发 `fast[0]` (`mcause = 16`) |
| `0x4000_6000` | **UART1** | 遥测/扩展串口（带深睡唤醒能力），触发 `fast[1]` (`mcause = 17`) |
| `0x4000_7000` | **SPI0** | SPI NOR 控制器（带硬件 WIP 轮询中断），触发 `fast[4]` (`mcause = 20`) |
| `0x4000_B000` | **RTC (AON)** | 常开域秒计数器 + 唤醒闹钟 + 1 Hz Tick，触发 `fast[5]` (`mcause = 21`) |

---

## 4. 时钟、复位与低功耗深睡架构

### 4.1 三异步时钟域与严格 CDC 隔离
1. **`clk_i` (16 MHz 主时钟)**：
   - **常开分支**：仅驱动 `apb_sysctrl` (PMU 状态机)、`apb_rtc` APB 接口侧与 `Debug Module`。
   - **门控分支 (`clk_sys`)**：经 SKY130 原生集成时钟门控单元 (`sky130_fd_sc_hd__dlclkp`) 门控后驱动 CPU、总线、SRAM 及全部常规外设。
2. **`rtc_clk_i` (32.768 kHz 低频晶振)**：独立驱动 RTC 计数器与 WDT 看门狗计数器。
3. **`jtag_tck_i` (JTAG 测试时钟)**：独立驱动 JTAG TAP 控制器。
* 所有跨时钟域信号均通过专用 `soc_cdc.sv` 模块（两级同步器、格雷码或握手机制）严格收敛，无未约束异步路径。

### 4.2 深睡进入与多源异步唤醒
* **硬件判定的深睡进入条件**：当固件置位 `PMU_CTRL.DEEP_EN` 并执行 `wfi` 指令使 Ibex 进入 `core_sleep` 状态，且硬件自动检测到 **UART0/1、SPI0、I2C0 全部处于空闲 (`!busy`)** 且无挂起唤醒源时，PMU 自动关断 `clk_sys`——门控域动态翻转归零，仅 `clk_i` 常开分支（PMU / RTC / Debug Module）保持活动（静态漏电地板约 `145 µW`）。
* **三大异步唤醒源**：
  1. **RTC 定时闹钟中断**（周期性传感器采样唤醒）；
  2. **UART1 RX 外部下降沿**（主机远程指令唤醒）；
  3. **JTAG Debug 停机请求**（开发调试强制唤醒，不可屏蔽）。

### 4.3 分级复位架构
* **上电复位 (`rst_ni`)**：复位 PMU、RTC 走时域与 Debug Module。
* **系统软/看门狗复位 (`sys_rst_n`)**：异步置位、两级同步释放，在 WDT 超时或 JTAG `ndmreset` 请求时保持 16 个时钟周期低电平，复位 CPU 与业务外设，**同时完整保留 `RSTCAUSE` 与 `SCRATCH` 现场供固件诊断**。

---

## 5. 全链路仿真验证闭环 (Verification Matrix)

本项目配备覆盖全功能的自动化回归测试套件（Verilator + C 固件 + 板级外设行为模型）：

* **T1 全功能与深睡唤醒回归**：
  ROM 从 SPI NOR 冷启动 → SRAM 读写 → SPI NOR WIP 硬件自动轮询中断 → 64 位定时器中断 → RTC 走时与闹钟深睡唤醒 → I2C 传感器读取（含 SHT3x 温湿度与 ADS1115 时钟拉伸测试）→ UART1 收发、回显与帧错误恢复 → 深睡下 UART1 RX 唤醒 → GPIO 中断 → AON WDT 喂狗与故意超时复位 → 重启后核对 `RSTCAUSE` 标志，最终输出 `ALL_PASS`。
* **T2 启动异常保护回归**：
  模拟空白或损坏的 SPI NOR Flash 镜像，验证 Boot ROM 安全拦截并输出 `BOOT ERR` 告警码。
* **T3 JTAG 跨深睡硬件调试回归**：
  在 T1 基础上通过 JTAG 位流驱动 `IDCODE`/`DTMCS`、挂起 CPU、通过 Abstract Command 读取 `dpc`/`sp`、通过 SBA 直接读写系统内存、在芯片处于 Deep-Sleep 关钟状态下发起 JTAG 唤醒停机，并在最后触发 `ndmreset` 验证调试复位链路。
