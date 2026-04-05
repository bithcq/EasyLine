# EasyLine

[中文](./README.zh-CN.md)

## Overview

EasyLine is a lightweight drawing tool for the MetaTrader 5 chart window. It is designed to make horizontal, vertical, and trend-line drawing faster while preserving the native MT5 workflow as much as possible.

It is built for discretionary chart work where fast manual markup matters:

- a compact toolbar with minimal chart obstruction
- OHLC snap when the cursor is close, free placement when it is not
- horizontal-line expansion levels derived from an `H / L` baseline pair
- automatic labels for derived MM / Fibonacci levels
- right-click exits drawing mode without immediately opening the MT5 context menu

## Features

- `8` horizontal `40x40` buttons: red, yellow, green, blue, horizontal line, vertical line, trend line, clear
- transparent dashed frames with purple line icons for the last 4 tool buttons
- thicker white border for selected color and tool states
- draggable toolbar that temporarily disables chart dragging while being moved
- single-click the clear button to enter single-line delete mode, double-click it to remove all EasyLine lines from the current chart
- in delete mode, the nearest EasyLine line is highlighted automatically and can be removed with one left-click
- preview and final line width unified at `2`
- horizontal-line expansion levels based on the current `H / L` baseline pair
- derived horizontal lines display labels on the right side, with level hints shown near the cursor during snapping
- deleting an EasyLine horizontal line also removes its label

## Horizontal Level Logic

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

## Installation & Usage

1. Copy [`easyline.mq5`](./easyline.mq5) into the MT5 `MQL5/Indicators` directory.
2. Compile it with MetaEditor.
3. Attach the indicator to any chart.
4. Choose a color and a tool, then left-click on the chart to place lines.
5. Right-click to exit the current drawing mode.
6. Single-click the clear button to enter single-line delete mode, or double-click it to remove all EasyLine-created lines from the current chart.

## Toolbar

| Order | Function |
| --- | --- |
| 1 | Red |
| 2 | Yellow |
| 3 | Green |
| 4 | Blue |
| 5 | Horizontal line |
| 6 | Vertical line |
| 7 | Trend line |
| 8 | Delete / Clear all |

## Interaction Notes

- The cursor snaps to OHLC points only when it is close enough; otherwise placement stays free
- In horizontal-line mode, derived MM / Fib levels have higher priority than regular OHLC snapping
- If a left-click lands on an existing chart object first, the current drawing action is still completed using that click position
- Single-clicking the clear button enters delete mode, double-clicking it clears all EasyLine lines, and toolbar dragging is not treated as a double-click
- In delete mode, the nearest EasyLine line under the cursor becomes the active delete target
- Exiting drawing mode or delete mode with right-click does not immediately trigger the native MT5 context menu on the same click

## Project Structure

- [`easyline.mq5`](./easyline.mq5): main MT5 indicator implementation
- [`README.md`](./README.md): repository landing page and language selector
- [`README.zh-CN.md`](./README.zh-CN.md): Chinese documentation
- [`README.en.md`](./README.en.md): English documentation

## Repository Note

This repository is intentionally focused on a single-file MT5 tool so the workflow stays simple, direct, and easy to maintain.
