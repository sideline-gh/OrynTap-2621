"""OrynTap · Stage 2 Part C: draws the three charts from the CSV results of analysis/queries.sql.
Usage: python3 analysis/make_charts.py <folder with q1.csv q2.csv q3.csv>"""
import csv, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from collections import defaultdict
INK, MUT, GRID, SURF = "#1f1f1e", "#5f5e5a", "#e4e3df", "#ffffff"
COL = {"AITU": "#2a78d6", "NU": "#eb6834", "MNU": "#1baf7a", "ENU": "#eda100"}
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10.5, "axes.edgecolor": GRID, "axes.labelcolor": MUT,
                     "xtick.color": MUT, "ytick.color": INK, "axes.titlelocation": "left"})
import sys, os
D = sys.argv[1] if len(sys.argv) > 1 else "."          # folder with q1.csv, q2.csv, q3.csv (exported from the SQL Editor)
os.chdir(D)
N_FINISHED = sum(int(r["check_ins"]) for r in csv.DictReader(open("q3.csv")))
SRC = "Source: OrynTap database, table check_ins (generated test data, " + str(N_FINISHED) + " finished check-ins), query Q{n} in analysis/queries.sql"
def finish(fig, n, name):
    fig.text(0.01, 0.01, SRC.format(n=n), fontsize=8.5, color=MUT, ha="left")
    fig.savefig(name, dpi=200, facecolor=SURF); print(name)

# Q1: line, check-ins started per hour (all 18 spaces) + per university thin lines
rows = list(csv.DictReader(open("q1.csv")))
tot = defaultdict(int); per = defaultdict(dict)
for r in rows:
    h = int(r["hour_of_day"]); n = int(r["check_ins"]); tot[h] += n; per[r["university"]][h] = n
hrs = list(range(8, 22))
fig, ax = plt.subplots(figsize=(9, 4.3))
ax.plot(hrs, [tot.get(h, 0) for h in hrs], color="#2a78d6", lw=2.4, marker="o", ms=5, zorder=3, label="All 4 universities")
pk = max(hrs, key=lambda h: tot.get(h, 0))
ax.annotate(f"peak {pk}:00 · {tot[pk]} check-ins", (pk, tot[pk]), xytext=(10, 6), textcoords="offset points", fontsize=9.5, color=INK)
ax.set_xticks(hrs, [f"{h}:00" for h in hrs], rotation=0, fontsize=8.8)
ax.set_xlabel("Hour of the day the check-in started (Astana time, UTC+5)")
ax.set_ylabel("Check-ins started (count)")
ax.set_ylim(0, max(tot.values()) * 1.18)
ax.grid(axis="y", color=GRID, lw=.8); ax.set_axisbelow(True); [ax.spines[s].set_visible(False) for s in ("top", "right")]
ax.set_title("Q1. When do students start studying? Check-ins per hour of the day", fontsize=12, color=INK, fontweight="bold", pad=12)
fig.tight_layout(rect=(0, 0.04, 1, 1)); finish(fig, 1, "chart_q1_hours.png")

# Q2: horizontal bars, check-ins per 100 seats, coloured by university
rows = list(csv.DictReader(open("q2.csv")))
rows.sort(key=lambda r: float(r["check_ins_per_100_seats"]))
fig, ax = plt.subplots(figsize=(9, 6.6))
y = range(len(rows))
ax.barh(y, [float(r["check_ins_per_100_seats"]) for r in rows], color=[COL[r["university"]] for r in rows], height=0.68, edgecolor="white", linewidth=1.5)
for i, r in enumerate(rows):
    ax.text(float(r["check_ins_per_100_seats"]) + 0.8, i, f'{float(r["check_ins_per_100_seats"]):.1f}  ({r["check_ins"]} check-ins / {r["seats"]} seats)', va="center", fontsize=8.6, color=INK)
ax.set_yticks(list(y), [f'{r["space"]} ({r["university"]})' for r in rows], fontsize=9)
ax.set_xlabel("Check-ins per 100 seats (all finished check-ins)")
ax.set_xlim(0, 95)
ax.grid(axis="x", color=GRID, lw=.8); ax.set_axisbelow(True); [ax.spines[s].set_visible(False) for s in ("top", "right")]
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color=c, label=u) for u, c in COL.items()], frameon=False, loc="lower right", title="University", fontsize=9)
ax.set_title("Q2. Which spaces are used most for their size?", fontsize=12, color=INK, fontweight="bold", pad=12)
fig.tight_layout(rect=(0, 0.035, 1, 1)); finish(fig, 2, "chart_q2_spaces.png")

# Q3: table (exact values matter)
rows = list(csv.DictReader(open("q3.csv")))
fig, ax = plt.subplots(figsize=(9, 2.6)); ax.axis("off")
head = ["Time chosen", "Finished check-ins", "Average real stay", "Pressed Leave early", "Ended by itself"]
cells = [[f'{r["planned_hours"]} h ({int(r["planned_hours"])*60} min)', r["check_ins"], f'{r["avg_stay_min"]} min', f'{r["pct_left_early"]} %', f'{r["pct_ended_by_itself"]} %'] for r in rows]
tot_n = sum(int(r["check_ins"]) for r in rows)
w_auto = round(sum(int(r["check_ins"]) * int(r["pct_ended_by_itself"]) for r in rows) / tot_n)
w_stay = round(sum(int(r["check_ins"]) * int(r["avg_stay_min"]) for r in rows) / tot_n)
cells.append(["All", str(tot_n), f"{w_stay} min", f"{100 - w_auto} %", f"{w_auto} %"])
tb = ax.table(cellText=cells, colLabels=head, loc="center", cellLoc="center", colLoc="center")
tb.auto_set_font_size(False); tb.set_fontsize(10); tb.scale(1, 1.6)
for (r, c), cell in tb.get_celld().items():
    cell.set_edgecolor(GRID)
    if r == 0: cell.set_facecolor("#e9eef5"); cell.set_text_props(fontweight="bold", color=INK)
    if r == len(cells): cell.set_text_props(fontweight="bold")
ax.set_title("Q3. How long do students stay, and how often does a check-in end by itself?", fontsize=12, color=INK, fontweight="bold", loc="left")
fig.tight_layout(rect=(0, 0.06, 1, 1)); finish(fig, 3, "chart_q3_stay_table.png")
print("total q1", sum(tot.values()), "peak", pk, tot[pk], "weighted auto", w_auto)
