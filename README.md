# EasyLine

## 中文简介

EasyLine 是一个运行在 MetaTrader 5 图表窗口中的轻量级划线工具，目标是用尽可能少的操作完成常用横线、竖线和折线绘制，同时尽量保留 MT5 原生交互习惯。

它适合需要高频手动画线、快速做区间参照和价格层级标记的交易场景，重点解决以下问题：

- 工具条占用空间小，进入图表后即可直接使用
- 鼠标靠近 OHLC 点时自动吸附，不靠近时允许自由落点
- 横线支持基于 `H / L` 基准区间的 `MM / Fib` 扩展吸附
- 派生横线会自动显示名称，便于识别关键价格层级
- 右键结束划线时不会立刻弹出 MT5 原生右键菜单

## English Overview

EasyLine is a lightweight drawing tool for the MetaTrader 5 chart window. It is designed to make horizontal, vertical, and trend-line drawing faster while preserving the native MT5 workflow as much as possible.

It is built for discretionary chart work where fast manual markup matters:

- a compact toolbar with minimal chart obstruction
- OHLC snap when the cursor is close, free placement when it is not
- horizontal-line expansion levels derived from an `H / L` baseline pair
- automatic labels for derived MM / Fibonacci levels
- right-click exits drawing mode without immediately opening the MT5 context menu

## 核心功能 / Features

- `8` 个 `40x40` 按钮横向排列，依次为红、黄、绿、蓝、横线、竖线、折线、清除
- 后 4 个功能按钮使用透明背景虚线框，内部为紫色实线图标
- 颜色和线型选中态使用更粗的白色边框显示
- 工具条支持拖动，拖动时会临时禁用图表自身拖动
- 横线、竖线、折线预览和最终线宽统一为 `2`
- 横线支持基于最近基准 `H / L` 的派生价格吸附
- 派生横线名称显示在横线右侧，鼠标靠近派生吸附位时会在鼠标旁显示当前名称
- 删除 EasyLine 横线时会同步删除对应名称标签

## 横线扩展逻辑 / Horizontal Level Logic

### 中文

当最近两根非派生 EasyLine 横线第一次形成基准后：

- 高价线自动标记为 `H`
- 低价线自动标记为 `L`
- 后续横线模式会优先吸附以下派生价格位：
  - `38.2`
  - `50`
  - `61.8`
  - `1M`
  - `2M`
  - `138.2`
  - `161.8`
  - `261.8`

补充规则：

- `H / L` 建立后不会因为后续再画普通横线而轮换
- 只有当原有 `H` 或 `L` 被删除导致基准失效时，才会重新建立新的 `H / L`
- 派生横线不会参与基准线轮换

### English

Once the first valid pair of non-derived EasyLine horizontal lines is established:

- the higher line is labeled `H`
- the lower line is labeled `L`
- horizontal drawing mode will then try these derived levels first:
  - `38.2`
  - `50`
  - `61.8`
  - `1M`
  - `2M`
  - `138.2`
  - `161.8`
  - `261.8`

Additional rules:

- `H / L` stays fixed after it is established
- a new `H / L` pair is created only if the original baseline becomes invalid after deletion
- derived horizontal lines never replace the baseline pair

## 安装与使用 / Installation & Usage

### 中文

1. 将 [`easyline.mq5`](./easyline.mq5) 放到 MT5 的 `MQL5/Indicators` 目录中。
2. 使用 MetaEditor 编译。
3. 将指标挂到任意图表。
4. 选择颜色和线型后，在图表中左键落点绘制。
5. 右键退出当前划线状态。
6. 点击清除按钮删除当前图表上的全部 EasyLine 线条。

### English

1. Copy [`easyline.mq5`](./easyline.mq5) into the MT5 `MQL5/Indicators` directory.
2. Compile it with MetaEditor.
3. Attach the indicator to any chart.
4. Choose a color and a tool, then left-click on the chart to place lines.
5. Right-click to exit the current drawing mode.
6. Use the clear button to remove all EasyLine-created lines from the current chart.

## 工具条说明 / Toolbar

| 顺序 / Order | 中文 | English |
| --- | --- | --- |
| 1 | 红色 | Red |
| 2 | 黄色 | Yellow |
| 3 | 绿色 | Green |
| 4 | 蓝色 | Blue |
| 5 | 横线 | Horizontal line |
| 6 | 竖线 | Vertical line |
| 7 | 折线 | Trend line |
| 8 | 清除 | Clear |

## 交互约定 / Interaction Notes

### 中文

- 鼠标靠近 OHLC 点时会吸附，不靠近时按光标原始位置落点
- 横线模式下，派生吸附优先于普通 OHLC 吸附
- 如果左键先命中图表对象，仍会按当前点击坐标继续完成划线
- 右键结束划线时，不会用同一次右击立刻触发 MT5 原生右键菜单

### English

- The cursor snaps to OHLC points only when it is close enough; otherwise placement stays free
- In horizontal-line mode, derived MM / Fib levels have higher priority than regular OHLC snapping
- If a left-click lands on an existing chart object first, the current drawing action is still completed using that click position
- Exiting drawing mode with right-click does not immediately trigger the native MT5 context menu on the same click

## 项目结构 / Project Structure

- [`easyline.mq5`](./easyline.mq5): main MT5 indicator implementation
- [`README.md`](./README.md): repository-facing overview

## 仓库说明 / Repository Note

### 中文

这个仓库目前聚焦于一个单文件 MT5 工具实现，保持依赖简单、部署直接、便于手工维护。

### English

This repository is intentionally focused on a single-file MT5 tool so the workflow stays simple, direct, and easy to maintain.
