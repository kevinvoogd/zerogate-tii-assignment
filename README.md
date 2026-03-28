# TienKung Humanoid Training on NVIDIA Brev

End-to-end pipeline for training the TienKung humanoid locomotion policy on a Brev cloud GPU instance. Everything runs headless inside a Docker container; policy playbacks are recorded to MP4 via Isaac Sim's offscreen renderer.

---

## Repo Contents

| File / Folder | Purpose |
|---|---|
| `setup_script.sh` | Brev VM bootstrap — paste into Brev's setup script field; runs on first boot |
| `Dockerfile` | Builds `tienkung-isaaclab:2.1.0` with TienKung + RSL_RL baked in |
| `docker-compose.yml` | Single persistent container + bind mounts for all outputs to `~/results/` |
| `docs/architecture.md` | Assumptions, constraints, system diagram, data flow |
| `docs/installation.md` | Phase 1 — Brev VM setup, NGC login, image build & verify |
| `docs/data_preparation.md` | Phases 2–4 — AMASS download, GMR retargeting, AMP data conversion |
| `docs/training.md` | Phases 5–6 — training, policy playback, results retrieval |
| `docs/troubleshooting.md` | Troubleshooting table + quick-reference command cheat-sheet |


---

## Prerequisites

You need accounts / keys for four services before starting:

| # | Service | What for | URL |
|---|---------|----------|-----|
| 1 | **NVIDIA NGC** | Pull `isaac-lab:2.1.0` base image + API key for `setup_script.sh` | https://ngc.nvidia.com/setup/api-key |
| 2 | **NVIDIA Brev** | Cloud GPU VM (L40S / ≥24 GB VRAM) | https://brev.nvidia.com |
| 3 | **AMASS** | SMPLX motion capture sequences (free registration) | https://amass.is.tue.mpg.de/ |
| 4 | **SMPL-X** | Body model `.pkl` files (free registration) | https://smplx.is.tue.mpg.de/ |

---

## Architecture Overview

```
Brev Host VM
├── ~/TienKung-Lab/         bind-mounted → /workspace/TienKung-Lab  (live source)
├── ~/GMR/                  gmr conda env on host (retargeting only)
├── ~/data/                 bind-mounted → /workspace/data
│   ├── amass/              AMASS .npz motion files  (manual download)
│   └── smplx/              SMPL-X body model .pkl   (manual download)
└── ~/results/              all outputs — user-owned, rsync-able
    ├── gmr/                GMR output: retargeted .pkl + visualizations
    ├── logs/               training checkpoints + TensorBoard events
    ├── videos/             policy playback MP4s
    └── datasets/           AMP motion data

Docker container: tienkung  (tienkung-isaaclab:2.1.0)
├── Isaac Lab  2.1.0  +  Isaac Sim  4.5.0
├── TienKung-Lab + RSL_RL baked in at build time
└── Bind mounts:  ~/results/* → /workspace/results/*
                  ~/TienKung-Lab → /workspace/TienKung-Lab
                  ~/data        → /workspace/data
```

**Data flow:**
```
AMASS .npz ──► GMR (host conda) ──► ~/results/gmr/tienkung_motion.pkl
                                              │
                                   ┌──────────▼─────────────────────┐
                                   │  tienkung container             │
                                   │  Phase 4: data conversion       │
                                   │  Phase 5: train  ──► logs/      │
                                   │  Phase 6: play   ──► videos/    │
                                   └─────────────────────────────────┘
```

---

## Phase 1 — Brev VM Setup and Docker Image Build

### 1.1 Create a Brev Instance

1. Log in at https://brev.nvidia.com → **Launchables → Create Launchable**
2. Choose **VM Mode — Basic VM with Python installed**
3. Set **NGC_API_KEY** in Brev's "Environment Variables" panel (key from https://ngc.nvidia.com/setup/api-key)
4. Paste the contents of `setup_script.sh` as the setup script
5. Choose a GPU instance with ≥ 24 GB VRAM (e.g. AWS g6e.4xlarge — L40S)
6. Set disk ≥ **300 GB** (Isaac Sim base image is ~15 GB)

### 1.2 What `setup_script.sh` does on first boot

The script runs automatically and:
- Clones `assignment_tii`, `TienKung-Lab`, and `GMR`
- Creates `~/data/{amass,smplx}` and `~/results/{gmr,logs,videos,datasets}`
- Installs Miniconda and creates the `gmr` conda env on the host
- Applies the SMPLX `.npz` → `.pkl` extension fix
- Logs in to NGC and builds the Docker image (requires `NGC_API_KEY` to be set)

### 1.3 Verify setup completed

```bash
conda env list                        # must show 'gmr'
ls ~/data/ ~/results/                 # both must exist
ls ~/TienKung-Lab/                    # must show the cloned repo
docker images | grep tienkung         # must show tienkung-isaaclab:2.1.0
```

### 1.4 If the Docker image is missing (`NGC_API_KEY` was not set at boot)

```bash
export NGC_API_KEY=<your key from https://ngc.nvidia.com/setup/api-key>

echo "$NGC_API_KEY" | docker login nvcr.io \
    --username '$oauthtoken' --password-stdin

docker build -t tienkung-isaaclab:2.1.0 ~/assignment_tii/
# First build: ~20–40 min — subsequent builds use layer cache
```

> **If `isaac-lab:2.1.0` is not on NGC:** uncomment the fallback block in `Dockerfile` (builds Isaac Lab from source on top of `isaac-sim:4.5.0`). Check availability: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/isaac-lab

### 1.5 Verify the image

```bash
docker run --gpus all --rm tienkung-isaaclab:2.1.0 \
    /workspace/isaaclab/isaaclab.sh -p -c \
    "import legged_lab; print('TienKung-Lab OK')"
```

---

## Phase 2 — Download AMASS Data (Manual, One-Time)

### 2.1 Register and download

| Resource | URL |
|----------|-----|
| AMASS dataset | https://amass.is.tue.mpg.de/ |
| SMPL-X models | https://smplx.is.tue.mpg.de/ |

### 2.2 Transfer files to the Brev host

Run from **your local machine** (`rsync` is preferred — it is resumable on failure):

```bash
# SMPL-X body model zip (~300 MB, one-time)
rsync -avz --progress ~/Downloads/models_smplx_v1_1.zip ubuntu@<brev-ip>:~/

# AMASS archives (can be several GB — rsync is essential)
rsync -avz --progress ~/Downloads/CMU.tar.bz2 ubuntu@<brev-ip>:~/data/amass/
```

### 2.3 Extract SMPL-X body models (on Brev host)

Body model files must land at the path GMR hardcodes:
```
~/GMR/assets/body_models/smplx/SMPLX_NEUTRAL.pkl
~/GMR/assets/body_models/smplx/SMPLX_MALE.pkl
~/GMR/assets/body_models/smplx/SMPLX_FEMALE.pkl
```

```bash
unzip -l ~/models_smplx_v1_1.zip | head -20   # check inner structure first
mkdir -p ~/GMR/assets/body_models/smplx
unzip ~/models_smplx_v1_1.zip -d /tmp/smplx_extract
mv /tmp/smplx_extract/models/smplx/*.pkl ~/GMR/assets/body_models/smplx/
rm -rf /tmp/smplx_extract
ls ~/GMR/assets/body_models/smplx/             # verify
```

### 2.4 Extract AMASS archives

```bash
mkdir -p ~/data/amass && cd ~/data/amass
for f in ~/data/amass/*.tar.bz2; do
    echo "Extracting $f ..."
    tar -xjf "$f" -C ~/data/amass/
done
ls ~/data/amass/CMU/    # verify: shows 01/ 02/ 03/ ...
```

### 2.5 Fix SMPLX `.npz` vs `.pkl` extension

The `smplx` package defaults to `.npz` but SMPL-X ships `.pkl`. `setup_script.sh` applies this fix automatically; only needed if you skipped the setup script:

```bash
sed -i "s/ext: str = 'npz'/ext: str = 'pkl'/" \
    ~/miniconda3/envs/gmr/lib/python3.10/site-packages/smplx/body_models.py
```

---

## Phase 3 — GMR Motion Retargeting (Brev Host)

GMR runs on the **host** in the `gmr` conda env. Output lands in `~/results/gmr/`
which is bind-mounted into the container as `/workspace/results/gmr`.

### 3.1 Single file (verify + intermediate result video)

```bash
conda activate gmr && cd ~/GMR

python scripts/smplx_to_robot.py \
    --smplx_file ~/data/amass/CMU/01/01_01_poses.npz \
    --robot tienkung \
    --save_path ~/results/gmr/tienkung_walk.pkl \
    --record_video --video_path ~/results/gmr/walk_retarget.mp4
```

The `.mp4` is the **intermediate result** for the retargeting stage.
Omit `--record_video` if running fully headless.

### 3.2 Batch (whole dataset folder)

`smplx_to_robot_dataset.py` recurses all subfolders of `--src_folder` automatically:

```bash
python scripts/smplx_to_robot_dataset.py \
    --src_folder ~/data/amass/CMU/ \
    --tgt_folder ~/results/gmr/ \
    --robot tienkung \
    --num_cpus 4
```

Re-run safe: existing `.pkl` files are skipped (add `--override` to force redo).

```bash
ls -lhR ~/results/gmr/    # verify output
```

---

## Phase 4 — AMP Data Conversion (Inside Container)

```bash
docker compose up -d    # start the container if not already running
```

### 4.1 Convert PKL to visualization format

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/gmr_data_conversion.py \
    --input_pkl /workspace/results/gmr/tienkung_motion.pkl \
    --output_txt legged_lab/envs/tienkung/datasets/motion_visualization/motion.txt
```

Then set `amp_motion_files_display` in the walk task config to:
```
legged_lab/envs/tienkung/datasets/motion_visualization/motion.txt
```

### 4.2 Generate AMP expert data

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play_amp_animation.py \
    --task=walk --num_envs=1 \
    --headless \
    --save_path legged_lab/envs/tienkung/datasets/motion_amp_expert/motion.txt \
    --fps 30.0
```

Then set `amp_motion_files` in the walk task config to:
```
legged_lab/envs/tienkung/datasets/motion_amp_expert/motion.txt
```

---

## Phase 5 — Training (Headless)

### 5.1 Start the container

```bash
docker compose up -d
docker ps --filter name=tienkung    # verify it's running
```

### 5.2 Train walk policy

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/train.py \
    --task=walk --headless --logger=tensorboard --num_envs=4096
```

### 5.3 Train run policy

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/train.py \
    --task=run --headless --logger=tensorboard --num_envs=4096
```

### 5.4 Monitor with TensorBoard

Open a second terminal while training:

```bash
docker exec tienkung \
    /workspace/isaaclab/isaaclab.sh -p -m tensorboard.main \
    --logdir /workspace/TienKung-Lab/logs --host 0.0.0.0 --port 6006
```

Open `http://<brev-ip>:6006` in your browser (port 6006 is already mapped in `docker-compose.yml`).

---

## Phase 6 — Policy Playback and Video Recording

Isaac Sim's offscreen GPU renderer encodes MP4s without a display. Videos land in
`~/results/videos/` on the Brev host.

### 6.1 Record walk policy

```bash
# Latest training checkpoint
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play.py \
    --task=walk --num_envs=1 \
    --headless --video --video_length 500 \
    --checkpoint logs/walk/<timestamp>/model_<iter>.pt

# Pre-trained policy bundled in repo
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play.py \
    --task=walk --num_envs=1 \
    --headless --video --video_length 500 \
    --checkpoint Exported_policy/walk.pt
```

### 6.2 Sim2Sim transfer (MuJoCo)

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/sim2sim.py \
    --task walk --policy Exported_policy/walk.pt --duration 100
```

---

## Results

All outputs land in `~/results/` on the Brev host — user-owned bind mounts, directly rsync-able.

```
~/results/
├── gmr/         GMR retargeting output (.pkl + motion visualizations)
├── logs/        training checkpoints + TensorBoard event files
├── videos/      recorded MP4 policy playbacks
└── datasets/    AMP expert motion data
```

| Output | Host path | Survives `compose down`? | Survives VM deletion? |
|--------|-----------|-------------------------|-----------------------|
| GMR retargeting | `~/results/gmr/` | ✅ | ❌ rsync before deleting |
| Checkpoints | `~/results/logs/` | ✅ | ❌ rsync before deleting |
| Videos | `~/results/videos/` | ✅ | ❌ rsync before deleting |
| AMP datasets | `~/results/datasets/` | ✅ | ❌ rsync before deleting |
| Shader cache | named volume | ✅ | ❌ not needed |

> **Rule of thumb:** Stop the Brev instance (**not delete**) between sessions.
> Before deleting, rsync `~/results/` to your local machine.

### Download results to your local machine

```bash
# Everything
rsync -avz --progress ubuntu@<brev-ip>:~/results/ ./results/

# Just checkpoints
rsync -avz ubuntu@<brev-ip>:~/results/logs/ ./results/logs/

# Just videos
rsync -avz ubuntu@<brev-ip>:~/results/videos/ ./results/videos/

# One-shot archive before deleting the VM
ssh ubuntu@<brev-ip> "tar czf ~/tienkung-backup-\$(date +%Y%m%d).tar.gz ~/results/"
scp ubuntu@<brev-ip>:~/tienkung-backup-*.tar.gz ./
```

---

## Quick Reference

```bash
# ── Build ─────────────────────────────────────────────────────────────
docker login nvcr.io          # username: $oauthtoken  password: <NGC key>
docker build -t tienkung-isaaclab:2.1.0 ~/assignment_tii/

# ── Container lifecycle ───────────────────────────────────────────────
docker compose up -d          # start
docker compose down           # stop (volumes preserved)
docker compose down -v        # stop + delete ALL volumes
docker exec -it tienkung bash # interactive shell

# ── GMR (host, gmr conda env) ─────────────────────────────────────────
conda activate gmr && cd ~/GMR

# Single file:
python scripts/smplx_to_robot.py \
    --smplx_file ~/data/amass/CMU/01/01_01_poses.npz \
    --robot tienkung \
    --save_path ~/results/gmr/tienkung_walk.pkl \
    --record_video --video_path ~/results/gmr/walk_retarget.mp4

# Batch:
python scripts/smplx_to_robot_dataset.py \
    --src_folder ~/data/amass/CMU/ \
    --tgt_folder ~/results/gmr/ \
    --robot tienkung --num_cpus 4

# ── Phase 4: data conversion ──────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/gmr_data_conversion.py \
    --input_pkl /workspace/results/gmr/tienkung_motion.pkl \
    --output_txt legged_lab/envs/tienkung/datasets/motion_visualization/motion.txt

# ── Training ──────────────────────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/train.py \
    --task=walk --headless --logger=tensorboard --num_envs=4096

# ── TensorBoard ───────────────────────────────────────────────────────
docker exec tienkung \
    /workspace/isaaclab/isaaclab.sh -p -m tensorboard.main \
    --logdir /workspace/TienKung-Lab/logs --host 0.0.0.0 --port 6006
# open http://<brev-ip>:6006

# ── Playback + video ──────────────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play.py \
    --task=walk --num_envs=1 --headless --video --video_length 500 \
    --checkpoint Exported_policy/walk.pt

# ── Download results (run from your local machine) ────────────────────
rsync -avz --progress ubuntu@<brev-ip>:~/results/ ./results/
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `docker build` fails: `manifest not found` | `isaac-lab:2.1.0` not on NGC | Uncomment the fallback block in `Dockerfile` |
| `docker login nvcr.io` rejected | Wrong credentials | Username must be literally `$oauthtoken`; password is your NGC API key |
| `ModuleNotFoundError: legged_lab` | Volume mount shadowed baked-in install | `docker exec ... pip install -e /workspace/TienKung-Lab` |
| GMR `KeyError` on SMPLX data | Wrong ext setting | Re-run the Phase 2.5 `sed` fix |
| `--video` flag not recognised | Flag not in TienKung 2.1 | Wrap with `gym.wrappers.RecordVideo` (see `docs/training.md`) |
| TensorBoard port unreachable | Brev security group | Open port 6006 in the Brev instance network settings |
| Reward does not converge | Too few envs or bad AMP data | Increase `--num_envs`; verify motion quality with `play_amp_animation.py` first |

→ Full troubleshooting table: [docs/troubleshooting.md](docs/troubleshooting.md)

---

## Detailed Docs

| Document | Contents |
|----------|----------|
| [docs/architecture.md](docs/architecture.md) | Assumptions, constraints, known gaps, system diagram |
| [docs/installation.md](docs/installation.md) | Phase 1 — full Brev VM setup guide |
| [docs/data_preparation.md](docs/data_preparation.md) | Phases 2–4 — detailed AMASS, GMR, and data conversion steps |
| [docs/training.md](docs/training.md) | Phases 5–6 — training and video playback |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Full troubleshooting table + command cheat-sheet |

## Upstream Repositories

| Repository | Description |
|---|---|
| [YanjieZe/GMR](https://github.com/YanjieZe/GMR) | Motion retargeting from SMPLX to robot skeletons |
| [Open-X-Humanoid/TienKung-Lab](https://github.com/Open-X-Humanoid/TienKung-Lab) | TienKung humanoid training (Isaac Lab 2.1.0) |
| [NVIDIA Isaac Lab](https://github.com/isaac-sim/IsaacLab) | Reinforcement learning framework on Isaac Sim |
# zerogate-tii-assignment
# zerogate-tii-assignment
