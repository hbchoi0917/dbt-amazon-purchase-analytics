"""Render the project overview chart (README banner / LinkedIn thumbnail) from the built models.

Run after `dbt build`:
    pip install matplotlib
    python scripts/render_overview_chart.py [dev.duckdb] [docs/images/project_overview.png]

Reads int_monthly_revenue and mart_revenue_forecast, so the chart always matches the models.
Colors are a colorblind-validated categorical palette (blue / orange / aqua).
"""
import sys
from datetime import date

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.lines
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

db = sys.argv[1] if len(sys.argv) > 1 else "dev.duckdb"
out = sys.argv[2] if len(sys.argv) > 2 else "docs/images/project_overview.png"
con = duckdb.connect(db, read_only=True)
actual = con.sql("select revenue_month, revenue from main_intermediate.int_monthly_revenue order by 1").fetchall()
fc = con.sql("""select method, forecast_month, forecast_revenue, lower_80_revenue, upper_80_revenue
                from main_mart.mart_revenue_forecast
                where method in ('moving_average', 'seasonal_naive') order by method, forecast_month""").fetchall()

# Reference palette (validated): slot 1 blue, slot 2 orange, slot 3 aqua
SURFACE, INK, INK2, MUTED, GRID, AXIS = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
plt.rcParams.update({"font.family": "Liberation Sans", "text.color": INK})

fig = plt.figure(figsize=(12, 6.27), dpi=200, facecolor=SURFACE)

# ---- left column: title + three stat tiles -------------------------------------
fig.text(0.05, 0.86, "dbt  ·  DuckDB  ·  SQL", fontsize=13, color=MUTED, weight="bold")
fig.text(0.05, 0.655, "Amazon Purchase\nBehavior & Revenue\nForecasting", fontsize=27, weight="bold",
         linespacing=1.12, va="bottom")
fig.text(0.05, 0.585, "Real, consented purchase histories · 2018–2022", fontsize=12.5, color=INK2)

stats = [("1.85M", "real Amazon purchases"),
         ("6", "forecast methods backtested"),
         ("95", "data tests in dbt")]
for i, (value, label) in enumerate(stats):
    y = 0.405 - i * 0.135
    fig.patches.append(FancyBboxPatch((0.05, y), 0.32, 0.105, boxstyle="round,pad=0,rounding_size=0.012",
                                      transform=fig.transFigure, facecolor="#f3f2ee", edgecolor="none"))
    fig.text(0.07, y + 0.052, value, fontsize=24, weight="bold", va="center")
    fig.text(0.17, y + 0.052, label, fontsize=12.5, color=INK2, va="center")

# ---- right column: monthly spend + forecasts -----------------------------------
fig.text(0.45, 0.865, "Monthly panel spend, with 3-month forecasts", fontsize=13.5, weight="bold")
# legend row: short colored line keys, text in ink
keys = [("Actual", BLUE, "-"), ("Selected: moving avg. (80% band)", ORANGE, (0, (3, 2))),
        ("Seasonal naive", AQUA, (0, (3, 2)))]
x = 0.45
for text, color, style in keys:
    fig.add_artist(matplotlib.lines.Line2D([x, x + 0.025], [0.818, 0.818], transform=fig.transFigure,
                                           color=color, linewidth=2, linestyle=style))
    t = fig.text(x + 0.032, 0.818, text, fontsize=11, color=INK2, va="center")
    fig.canvas.draw()
    bb = t.get_window_extent().transformed(fig.transFigure.inverted())
    x = bb.x1 + 0.025

ax = fig.add_axes([0.45, 0.12, 0.50, 0.64], facecolor=SURFACE)
xs = [r[0] for r in actual]
ys = [float(r[1]) for r in actual]
ax.axvspan(date(2022, 10, 16), date(2023, 2, 28), color="#f3f2ee", linewidth=0, zorder=0)
ax.text(date(2022, 12, 20), 1250000, "Forecast", fontsize=10.5, color=MUTED, ha="center", va="center")
ax.fill_between(xs, ys, color=BLUE, alpha=0.10, linewidth=0)
ax.plot(xs, ys, color=BLUE, linewidth=2, solid_joinstyle="round", solid_capstyle="round")

last_x, last_y = xs[-1], ys[-1]
for method, color in (("seasonal_naive", AQUA), ("moving_average", ORANGE)):
    rows = [r for r in fc if r[0] == method]
    fx = [last_x] + [r[1] for r in rows]
    fy = [last_y] + [float(r[2]) for r in rows]
    if method == "moving_average":
        ax.fill_between([r[1] for r in rows], [float(r[3]) for r in rows], [float(r[4]) for r in rows],
                        color=ORANGE, alpha=0.12, linewidth=0)
    ax.plot(fx, fy, color=color, linewidth=2, linestyle=(0, (3, 2)))
    ax.scatter(fx[-1], fy[-1], s=64, color=color, edgecolor=SURFACE, linewidth=2, zorder=5)

ax.annotate("COVID shift", xy=(date(2020, 5, 1), 796896), xytext=(date(2019, 3, 1), 960000),
            fontsize=11, color=INK2, ha="center",
            arrowprops=dict(arrowstyle="-", color=MUTED, lw=1))
ax.annotate("Holiday peaks", xy=(date(2021, 12, 1), 1110890), xytext=(date(2021, 3, 1), 1235000),
            fontsize=11, color=INK2, ha="center", va="center",
            arrowprops=dict(arrowstyle="-", color=MUTED, lw=1))

ax.set_xlim(date(2018, 1, 1), date(2023, 2, 28))
ax.set_ylim(0, 1300000)
ax.set_yticks([0, 400000, 800000, 1200000])
ax.yaxis.set_major_formatter(lambda v, _: "$0" if v == 0 else (f"${v/1e6:.1f}M" if v >= 1e6 else f"${v/1e3:.0f}K"))
ax.xaxis.set_major_locator(mdates.YearLocator())
ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
ax.grid(axis="y", color=GRID, linewidth=1)
ax.set_axisbelow(True)
for side in ("top", "right", "left"):
    ax.spines[side].set_visible(False)
ax.spines["bottom"].set_color(AXIS)
ax.tick_params(colors=MUTED, labelsize=11, length=0, pad=6)

fig.savefig(out, dpi=200, facecolor=SURFACE)
print("saved", out)
