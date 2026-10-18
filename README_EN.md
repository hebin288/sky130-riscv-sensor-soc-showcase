# SKY130A RISC-V Low-Power Sensor SoC — Physical Implementation & Signoff Baseline

[中文版 README](README.md)

> Full open-source toolchain (Yosys/slang → LibreLane/OpenROAD → KLayout/Magic/Netgen/CVC), RTL to GDSII.
> All core `cf-precheck` signoff items pass (XOR / LVS / OEB / routing DRC / geometry rules); the 3 full-rule findings are waived items attributed cell-by-cell to hardened-IP internals.

A 32-bit RISC-V (`RV32IMC`) low-power SoC physical-implementation baseline on SkyWater **SKY130A**, targeting **custom sensor interfaces, industrial edge control, and research payloads**. Delivered in two forms: **MPW shuttle (ChipFoundry OpenFrame)** and a **standalone die (custom pad ring)**.

---

## Layout Overview

| OpenFrame top `openframe_project_wrapper` (3166 × 4766 µm) | Standalone die `chip_top` (3800 × 2016 µm) |
| :---: | :---: |
| ![OpenFrame Layout](assets/openframe_full.png) | ![Standalone Layout](assets/chip_r7_eco_full.png) |
| 15.09 mm² · hardened logic macro + 8×2KB SRAM + 44 GPIO | 7.66 mm² · 34×`gpiov2` + 8×power pads + 8×2KB SRAM |

| Hardened logic macro `soc_of_logic` (2400 × 1000 µm) | SRAM + top-level `met4/met5` power grid (zoom) |
| :---: | :---: |
| ![Logic Macro](assets/soc_of_logic_macro.png) | ![SRAM PDN](assets/sram_pdn_zoom.png) |
| Independently signed off, `met1–4` only; DRC/LVS/antenna all 0 | 8 SRAM power rings fed through 119 `met5` straps |

---

## Signoff Metrics

| Check | OpenFrame (`soc_of_w10`) | Standalone (`chip_r7_eco`) |
|---|---|---|
| Detailed-routing DRC | **0** (converged in 6 iterations) | **0** (converged in 17 iterations) |
| Netgen LVS | **`Circuits match uniquely`**, 0 pin mismatches | **`Circuits match uniquely`**, 0 pin mismatches |
| GDS boolean XOR | **0 diffs** (vs. official golden template) | **0 diffs** (DEF ↔ GDS) |
| CVC / OEB electrical rules | **0 errors** (all 44 GPIO configs identified) | N/A (custom pad ring) |
| Timing (tt, 3 corners @ 16 MHz) | setup / hold **0 / 0** | setup / hold **0 / 0** |
| PDN continuity | probes to all 119 `met5` straps pass, 0 opens / 0 shorts | 64 SRAM power pins 100% bonded, IR drop ≤ 13.5 µV |
| Antenna | logic macro 0; 256 SRAM output nets 0; 18 residual wrapper nets (known pad-boundary items) | 0 violating nets (2161 protection diodes) |
| Total power estimate | 19.5 mW (vectorless, default activity) | 4.47 mW (same basis) |
| Official full-rule KLayout | FEOL 3 / BEOL 264 / density 204 — **all inside OpenRAM hard macros**, filed as IP waivers | — |
| `cf-precheck` fast geometry | offgrid / zeroarea / spike / pin_label / topcell all PASS | N/A |

---

## Engineering Highlights

**Architecture & low power**
- Ibex RV32IMC + AHB-Lite/APB peripheral set (SPI-NOR boot, I²C, dual UART, GPIO, 64-bit timer) + RISC-V Debug Module (JTAG, SBA, debug across deep sleep);
- Three asynchronous clock domains (16 MHz main / 32.768 kHz always-on / JTAG TCK) converged through dedicated CDCs; the PMU gates the main clock tree once peripherals go idle, with three asynchronous wakeups (RTC alarm, UART1 RX, JTAG); deep-sleep static leakage floor ≈ 145 µW;
- Verilator + C-firmware automated regression: T1 (cold boot + all peripherals + deep-sleep wake + WDT reset recovery), T2 (corrupt NOR-image protection), T3 (JTAG debug across deep sleep).

**Physical implementation**
- Hierarchical hardening: the `soc_of_logic` macro is signed off standalone restricted to `met1–4`; the 8 OpenRAM SRAMs sit at top level, fed directly by the `met4/met5` power grid — this resolves the conflict between the sub-macro routing-layer limit and the SRAM power-ring supply requirement. Continuity verified by full-net tracing with KLayout `LayoutToNetlist`;
- `LVS_FLATTEN` for boundary power-connection macros (`vccd1_connection`/`vssd1_connection`), giving zero pin mismatches in official LVS;
- Cell-level attribution of flat full-GDS DRC: all 471 violations traced to cells inside the SRAM hard macros; user logic and routing region: 0 (see signoff-evidence doc).

---

## Documentation

- [Architecture spec: microarchitecture, memory map, clock/reset, verification matrix](docs/01_Architecture_Spec.md) *(Chinese)*
- [Physical signoff evidence: precheck item-by-item verification, engineering blockers, DRC attribution](docs/02_Physical_Signoff_Evidence.md) *(Chinese)*
- Tech notes *(Chinese)*
  - [`cf-precheck` mechanics and standalone-die applicability](docs/tech_notes/precheck说明.md)
  - [LibreLane clock-tree synthesis (TritonCTS) and clock skew](docs/tech_notes/librelane的cts.md)
  - [OpenSTA slack computation and multi-corner signoff criteria](docs/tech_notes/slack计算原理.md)
  - [Die-shape rationale and packaging paths (QFN / COB / chipIgnite)](docs/tech_notes/die_shape_and_packaging.md)
- [RTL sample: `apb_uart.sv` — APB UART with deep-sleep busy interlock and framing-error recovery](rtl_sample/apb_uart.sv)

---

## Working With Us

Services for **university research groups, early-stage silicon teams, and industrial sensor vendors**:

1. **Research tapeout vehicle**: integrate your custom block (sensor AFE, compute-in-memory/accelerator, security engine, …) on this baseline SoC; we deliver a tapeout-ready SKY130 / GF180 GDS plus test firmware;
2. **Shared tapeout**: the SoC's spare logic area and bus interfaces are open to teams with MPW plans — pool or trade shuttle resources;
3. **Physical back-end & signoff rescue**: RTL-to-GDSII implementation, specializing in multi-macro floorplans, PDN continuity, antenna/hold repair, LVS mismatches, and `cf-precheck` blockers;
4. **Custom ASIC prototypes**: full-flow delivery from spec, RTL, and verification through MPW tapeout and bring-up.

---

### Contact

- Email: `hebin_21cn@foxmail.com`
- WeChat: `BILLULM`

> This repository publishes the architecture spec, a sample module, and redacted signoff evidence only. Complete RTL, physical-implementation configs (`config.json` / `pdn.tcl` / `lvs_config.json`), and the GDS database are available to collaborators.

### License

- Code (`rtl_sample/` etc.): [Apache-2.0](LICENSE)
- Documentation & images (`README*.md`, `docs/`, `assets/`): [CC BY 4.0](LICENSE)
