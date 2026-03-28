# Architecture

System design, assumptions, and known constraints for the TienKung training pipeline.

---

## Assumptions and Constraints

| # | Item | Detail |
|---|------|--------|
| A1 | **Local compute is insufficient** | Isaac Lab parallel RL (4096 envs) requires ≥24 GB VRAM. Local hardware cannot run this. |
| A2 | **NVIDIA Brev is the target compute** | All steps target a Brev-provisioned AWS VM with an NVIDIA GPU (e.g. g6e.4xlarge — L40S). |
| A3 | **Docker is the execution environment** | TienKung training runs inside `tienkung-isaaclab:2.1.0`. GMR runs on the Brev host VM in a separate conda env. |
| A4 | **AMASS data requires manual registration** | AMASS SMPLX motions require a free account at https://amass.is.tue.mpg.de/ and https://smplx.is.tue.mpg.de/. Cannot be automated. |
| A5 | **TienKung is baked into the image** | `pip install -e .` runs at `docker build` time — installs persist across container restarts. Source is still bind-mounted for live editing. |
| A6 | **No browser viewer** | Everything is headless. Policy playback uses Isaac Sim's offscreen renderer (`--headless --video`). Videos go to `~/results/videos/` on the Brev host. |
| A7 | **NGC API key required** | Pulling `nvcr.io/nvidia/isaac-lab:2.1.0` requires a free NGC account and API key from https://ngc.nvidia.com/setup/api-key |
| A8 | **Results as bind mounts** | All outputs land in `~/results/` on the Brev host as bind mounts — user-owned, browsable, and rsync-able directly. Only the shader cache uses a named volume. `~/results/` survives `docker compose down` and image rebuilds. The Brev VM disk survives when the instance is **stopped**, but is lost on **deletion** — rsync `~/results/` before deleting. |

---

## Known Gaps

### Version Mismatch

TienKung-Lab targets **Isaac Lab 2.1.0 + Isaac Sim 4.5.0**. The Dockerfile pulls `nvcr.io/nvidia/isaac-lab:2.1.0` from NGC.

> **Check tag availability before building:**
> https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-lab

If `isaac-lab:2.1.0` does not exist on NGC, the Dockerfile contains a commented-out
fallback that builds Isaac Lab 2.1.0 from source on top of `isaac-sim:4.5.0`.
Uncomment that block.

### GMR Version Pin

`setup_script.sh` clones GMR at `main` (no version pin). If GMR introduces a breaking
change, pin to a specific commit:
```bash
cd ~/GMR && git checkout <commit-sha>
```

### SMPLX Model Files

GMR requires SMPL-X body model `.pkl` files downloaded separately:
```
~/data/smplx/SMPLX_NEUTRAL.pkl   # or SMPLX_MALE.pkl / SMPLX_FEMALE.pkl
```

---

## System Layout

```
Brev Host VM
├── ~/TienKung-Lab/         bind-mounted → /workspace/TienKung-Lab  (live source)
├── ~/GMR/                  gmr conda env on host (retargeting only)
├── ~/data/                 bind-mounted → /workspace/data  (inputs only)
│   ├── amass/              AMASS .npz motion files (manual download)
│   └── smplx/              SMPL-X body model .pkl (manual download)
└── ~/results/              all outputs — user-owned, rsync-able
    ├── gmr/                GMR output: retargeted .pkl + visualizations
    ├── logs/               training checkpoints + TensorBoard events
    ├── videos/             policy playback MP4s
    └── datasets/           AMP motion data

Docker container: tienkung  (tienkung-isaaclab:2.1.0)
├── Isaac Lab  2.1.0
├── Isaac Sim  4.5.0
├── TienKung-Lab + RSL_RL baked in at build time
├── Results bind mounts (host ~/results/)
│   ├── ~/results/gmr      → /workspace/results/gmr     (GMR output, Phase 4 input)
│   ├── ~/results/logs     → /workspace/TienKung-Lab/logs
│   ├── ~/results/videos   → /workspace/TienKung-Lab/videos
│   └── ~/results/datasets → /workspace/TienKung-Lab/legged_lab/envs/tienkung/datasets
└── Named volume
    └── tienkung-shader-cache → /root/.cache/ov  (Isaac Sim shader cache)
```

---

## Data Flow

```
AMASS .npz ──► GMR (host conda) ──► ~/results/gmr/tienkung_motion.pkl
                                              │
                                   ┌──────────▼──────────────────┐
                                   │  tienkung container          │
                                   │  Phase 4: data conversion    │
                                   │       ▼                      │
                                   │  Phase 4: AMP expert data    │
                                   │       ▼                      │
                                   │  Phase 5: train ──► logs/    │
                                   │       ▼                      │
                                   │  Phase 6: play  ──► videos/  │
                                   └──────────────────────────────┘
```
