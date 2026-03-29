#!/usr/bin/env python3
"""Export TensorBoard training curves as PDF plots for the LaTeX report.

Usage (from repo root):
    python scripts/export_tb_plots.py

Reads event files from logs/ and writes PDFs to latex/figures/.
"""

import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from tbparse import SummaryReader

REPO = Path(__file__).resolve().parent.parent
LOG_DIR = REPO / "logs"
FIG_DIR = REPO / "latex" / "figures"
FIG_DIR.mkdir(parents=True, exist_ok=True)

# Matplotlib defaults for LaTeX-friendly output
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 10,
    "axes.labelsize": 11,
    "axes.titlesize": 11,
    "legend.fontsize": 9,
    "xtick.labelsize": 9,
    "ytick.labelsize": 9,
    "figure.dpi": 150,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.05,
})

COLORS = {"walk": "#1f77b4", "run": "#ff7f0e"}


def load_run(task: str) -> "pd.DataFrame | None":
    """Load the most recent run for a given task, return pivoted scalars or None."""
    task_dir = LOG_DIR / task
    if not task_dir.exists():
        return None
    runs = sorted(task_dir.iterdir())
    if not runs:
        return None
    latest = runs[-1]
    reader = SummaryReader(str(latest), pivot=True)
    df = reader.scalars
    return df


def smooth(series, weight=0.6):
    """Exponential moving average smoothing."""
    smoothed = []
    last = series.iloc[0]
    for v in series:
        s = weight * last + (1 - weight) * v
        smoothed.append(s)
        last = s
    return smoothed


# ── Load data ────────────────────────────────────────────────────
walk_df = load_run("walk")
run_df = load_run("run")

if walk_df is None and run_df is None:
    print("No log data found in", LOG_DIR)
    raise SystemExit(1)

print("Available tasks:", ", ".join(
    t for t, d in [("walk", walk_df), ("run", run_df)] if d is not None
))


# ── 1. Total reward curve ────────────────────────────────────────
fig, ax = plt.subplots(figsize=(6, 3.5))
for task, df, color in [("walk", walk_df, COLORS["walk"]),
                         ("run", run_df, COLORS["run"])]:
    if df is None:
        continue
    col = "Train/mean_reward"
    sub = df[["step", col]].dropna()
    ax.plot(sub["step"], sub[col], alpha=0.25, color=color, linewidth=0.5)
    ax.plot(sub["step"], smooth(sub[col]), color=color, label=task.capitalize(),
            linewidth=1.5)

ax.set_xlabel("Iteration")
ax.set_ylabel("Mean Episode Reward")
ax.legend()
ax.grid(True, alpha=0.3)
fig.savefig(FIG_DIR / "training_reward.pdf")
print("Saved training_reward.pdf")
plt.close(fig)


# ── 2. Episode length curve ─────────────────────────────────────
fig, ax = plt.subplots(figsize=(6, 3.5))
for task, df, color in [("walk", walk_df, COLORS["walk"]),
                         ("run", run_df, COLORS["run"])]:
    if df is None:
        continue
    col = "Train/mean_episode_length"
    sub = df[["step", col]].dropna()
    ax.plot(sub["step"], sub[col], alpha=0.25, color=color, linewidth=0.5)
    ax.plot(sub["step"], smooth(sub[col]), color=color, label=task.capitalize(),
            linewidth=1.5)

ax.set_xlabel("Iteration")
ax.set_ylabel("Mean Episode Length (steps)")
ax.legend()
ax.grid(True, alpha=0.3)
fig.savefig(FIG_DIR / "training_episode_length.pdf")
print("Saved training_episode_length.pdf")
plt.close(fig)


# ── 3. Key reward components (2×2 grid) ─────────────────────────
components = [
    ("Episode_Reward/track_lin_vel_xy_exp", "Track Linear Vel (xy)"),
    ("Episode_Reward/track_ang_vel_z_exp", "Track Angular Vel (z)"),
    ("Episode_Reward/energy", "Energy Penalty"),
    ("Episode_Reward/action_rate_l2", "Action Rate Penalty"),
]

fig, axes = plt.subplots(2, 2, figsize=(7, 5), sharex=True)
for ax_item, (col, title) in zip(axes.flat, components):
    for task, df, color in [("walk", walk_df, COLORS["walk"]),
                             ("run", run_df, COLORS["run"])]:
        if df is None or col not in df.columns:
            continue
        sub = df[["step", col]].dropna()
        ax_item.plot(sub["step"], sub[col], alpha=0.25, color=color, linewidth=0.5)
        ax_item.plot(sub["step"], smooth(sub[col]), color=color, label=task.capitalize(),
                     linewidth=1.5)
    ax_item.set_title(title)
    ax_item.grid(True, alpha=0.3)
    ax_item.legend(fontsize=7)

for ax_item in axes[1]:
    ax_item.set_xlabel("Iteration")
fig.tight_layout()
fig.savefig(FIG_DIR / "reward_components.pdf")
print("Saved reward_components.pdf")
plt.close(fig)


# ── 4. AMP + PPO losses (2×2 grid) ──────────────────────────────
loss_components = [
    ("Loss/surrogate", "PPO Surrogate Loss"),
    ("Loss/value_function", "Value Function Loss"),
    ("Loss/amp", "AMP Loss"),
    ("Loss/entropy", "Entropy"),
]

fig, axes = plt.subplots(2, 2, figsize=(7, 5), sharex=True)
for ax_item, (col, title) in zip(axes.flat, loss_components):
    for task, df, color in [("walk", walk_df, COLORS["walk"]),
                             ("run", run_df, COLORS["run"])]:
        if df is None or col not in df.columns:
            continue
        sub = df[["step", col]].dropna()
        ax_item.plot(sub["step"], sub[col], alpha=0.25, color=color, linewidth=0.5)
        ax_item.plot(sub["step"], smooth(sub[col]), color=color, label=task.capitalize(),
                     linewidth=1.5)
    ax_item.set_title(title)
    ax_item.grid(True, alpha=0.3)
    ax_item.legend(fontsize=7)

for ax_item in axes[1]:
    ax_item.set_xlabel("Iteration")
fig.tight_layout()
fig.savefig(FIG_DIR / "training_losses.pdf")
print("Saved training_losses.pdf")
plt.close(fig)


# ── 5. Gait reward components ───────────────────────────────────
gait_components = [
    ("Episode_Reward/gait_feet_frc_perio", "Gait Force Periodicity"),
    ("Episode_Reward/gait_feet_spd_perio", "Gait Speed Periodicity"),
    ("Episode_Reward/feet_slide", "Feet Slide Penalty"),
    ("Episode_Reward/feet_y_distance", "Feet Y Distance"),
]

fig, axes = plt.subplots(2, 2, figsize=(7, 5), sharex=True)
for ax_item, (col, title) in zip(axes.flat, gait_components):
    for task, df, color in [("walk", walk_df, COLORS["walk"]),
                             ("run", run_df, COLORS["run"])]:
        if df is None or col not in df.columns:
            continue
        sub = df[["step", col]].dropna()
        ax_item.plot(sub["step"], sub[col], alpha=0.25, color=color, linewidth=0.5)
        ax_item.plot(sub["step"], smooth(sub[col]), color=color, label=task.capitalize(),
                     linewidth=1.5)
    ax_item.set_title(title)
    ax_item.grid(True, alpha=0.3)
    ax_item.legend(fontsize=7)

for ax_item in axes[1]:
    ax_item.set_xlabel("Iteration")
fig.tight_layout()
fig.savefig(FIG_DIR / "gait_rewards.pdf")
print("Saved gait_rewards.pdf")
plt.close(fig)


print(f"\nAll plots saved to {FIG_DIR}/")
