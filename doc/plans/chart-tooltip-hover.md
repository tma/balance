# Chart Tooltip Hover Interactions

## Problem
All SVG charts (donut and bar) only had native SVG `<title>` elements for hover info, which produce slow, plain-text browser-native tooltips with no styling.

## Solution
A single reusable Stimulus `chart-tooltip` controller that provides styled, positioned HTML tooltips on hover over any SVG chart element. Zero new dependencies — uses only Stimulus + CSS.

## Implementation

### New Files
- `app/javascript/controllers/chart_tooltip_controller.js` — Stimulus controller
  - Event delegation via `mouseenter`/`mouseleave` (capture phase) on the container
  - Targets any descendant with `data-tooltip` attribute
  - Positions tooltip anchored above the hovered element (centered horizontally), never below
  - Clamped to stay within the controller container bounds
  - Touch support (tap to show, tap same to dismiss, tap elsewhere to dismiss)
  - Bar group highlighting: elements sharing a `data-bar-group` attribute all highlight when any one is hovered (used for total rects above stacked bars)
- `app/views/shared/_chart_tooltip.html.erb` — Shared partial for tooltip div
  - Dark background (`bg-slate-900 text-slate-100 border-slate-700`) for dark mode
  - `pointer-events-none` to avoid interfering with hover detection
- `app/helpers/application_helper.rb` — Added `format_currency_plain` method
  - Returns plain text (no `<span>` wrapping) for use in `data-tooltip` attributes

### Modified Files
- `app/assets/stylesheets/application.css` — CSS hover highlight effect
  - `filter: brightness(1.2)` on hovered `[data-tooltip]` elements
  - No dimming of sibling segments (user preference)
- `app/views/dashboard/net_worth.html.erb` — 3 charts updated:
  - Donut chart: wrapped in controller, added `data-tooltip` to circles
  - Monthly bar chart: wrapped in controller, `data-tooltip` on segment rects, invisible total rects above bars, `data-bar-group` for whole-bar highlighting
  - Quarterly bar chart: same pattern as monthly
- `app/views/dashboard/cash_flow.html.erb` — 2 charts updated:
  - Saving rate donut: wrapped in controller, `data-tooltip` with `format_currency_plain`
  - Category breakdown donut: both expense and income ring segments
- `app/views/dashboard/home.html.erb` — 1 chart updated:
  - Small donut: wrapped in controller, `data-tooltip` on circles

### Design Decisions
- **Sticky/anchored positioning** — tooltip is centered above the hovered element, not following the mouse cursor
- **Always above** — tooltip always renders above the element, clamped to y=0 if near the top (never flips below)
- **No dimming** — hovering a segment does NOT dim other segments; only the hovered element gets a subtle `brightness(1.2)` highlight
- **Bar total rects** — invisible transparent `<rect>` elements above stacked bars show the bar's total on hover; hovering these highlights all segments in the bar via `data-bar-group`
- **Event delegation** over per-element `data-action` attributes — cleaner ERB, works automatically with dynamic content
- **`position: relative`** on container + `position: absolute` on tooltip — avoids overflow issues and works within Turbo morphing
- **No library dependencies** — aligns with project's Hotwire-only philosophy
- Bar chart tooltips include time period context (e.g., "Jan 2025 · Stocks: $50,000 (45%)")
