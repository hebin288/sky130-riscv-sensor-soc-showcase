# LibreLane STA 中 Slack 的计算原理

LibreLane 本身不计算时序——它把 OpenSTA（集成在 OpenROAD 里）当作引擎，多次调用并解析结果。本文说明 slack 的计算逻辑与本项目相关的验证细节。

---

## 一、 输入数据

每个 STA 步骤读入四类数据：

- **门级网表**（当前步骤的 Verilog/DEF）；
- **Liberty 时序库**（`.lib`，每个工艺角一份；sky130A 为 NLDM 查表模型——cell delay / output slew 都是 `input_slew × output_load` 的二维查表插值）；
- **SDC 约束**（时钟定义、input/output delay、异步时钟组）；
- **寄生参数**（布线前用估计 RC/wireload，布线后读真实 `SPEF`，按 corner 分开读：`read_spef -corner <name>`，见 `scripts/openroad/common/io.tcl:280`）。

## 二、 单条路径的 slack 公式

### Setup（max delay 检查）

```
arrival   = launch 时钟路径延迟 + 触发器 clk→q + 组合链 cell/net 延迟（全取 max）
required  = capture 时钟路径延迟 + 周期 T − 触发器 setup 时间 − uncertainty
slack     = required − arrival        （slack < 0 即违例）
```

### Hold（min delay 检查）

```
arrival   = launch 时钟路径 + clk→q + 组合链（全取 min）
required  = capture 时钟路径 + hold 时间 + uncertainty
slack     = arrival − required        （slack < 0 即违例）
```

其中 cell 延迟由 NLDM 表插值：**输入 slew**（上级门传播来的）× **输出负载**（SPEF 的 net RC + 下级 pin cap）。net 延迟用 SPEF 里的 RC 网络做 Elmore/D3M 等效。

## 三、 时钟路径的处理（LibreLane 按阶段切换）

关键变量是时钟路径用理想值还是实测值（见 `io.tcl:119` 起）：

| 阶段 | 时钟设置 | 含义 |
|---|---|---|
| 布局布线前（staprepnr） | `unset_propagated_clock` | 理想时钟，插入延迟用估计值，skew = 0 |
| CTS 之后（stamidpnr / grt） | `set_propagated_clock [all_clocks]` | 时钟树真实 buffer 延迟参与计算 |
| 布线后（stapostpnr） | propagated + SPEF | 最终签核口径，skew 也是实测值 |

## 四、 多 corner 与指标口径

`scripts/openroad/sta/corner.tcl` 对每个 `STA_CORNERS`（本项目为 `nom/min/max_tt_025C_1v80` 三角）独立 `define_corners`、读各自的 `.lib` + `.spef`，然后分别执行：

```tcl
report_checks -path_delay max ...   # setup 全路径表
report_checks -path_delay min ...   # hold 全路径表
worst_slack -corner <c> -min/-max   # → timing__hold/setup_ws__slack
total_negative_slack ...            # → TNS
find_timing_paths ... -slack_max 0  # → 违例计数 timing__*_vio__count
```

`metrics.json` 里的 `timing__setup_vio__count` = 该角 slack < 0 的 endpoint 数；对外报的"最差 slack"是三个角的 `worst_slack` 汇总取最劣。

## 五、 与本项目相关的两点

1. **`set_input_delay -min 0.5` 的作用位置**：它把数据到达时间的下限加进 `arrival`（min 路径），抬高 hold 的 arrival 端——这是 `soc_of_w6` 那 4 条 hold 违例的修法：逻辑宏硬化时按 `-min 0.5ns` 假设外部输入延迟，wrapper 不声明时 OpenSTA 按 0 算，等效于数据"瞬间到达"，从而触发 hold 违例；
2. **`format full_clock_expanded`**：报告里 launch/capture 时钟路径逐 cell 展开，可直接看到 slack 每一项的构成（见 `soc_of_w10` 的 `stapostpnr/*/max.rpt`）。

---

**一句话总结**：slack = 要求时间 − 到达时间（setup），或到达时间 − 要求时间（hold）。到达时间由 NLDM 查表延迟 + SPEF 寄生 + 实际时钟树延迟累加得出，按每个工艺角独立计算，任一角 < 0 即计为违例。
