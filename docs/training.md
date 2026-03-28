# Training, Playback, and Results

Train the walk/run policies, record playback videos, and retrieve results from the Brev host.

---

## Phase 5 — Training (Headless)

All phases share one persistent container. Start it once and leave it running.

### 5.1 Start the container

```bash
docker compose up -d
```

Verify it is running:
```bash
docker ps --filter name=tienkung
```

### 5.2 Train the Walk Policy

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/train.py \
    --task=walk --headless --logger=tensorboard --num_envs=4096
```

### 5.3 Train the Run Policy

```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/train.py \
    --task=run --headless --logger=tensorboard --num_envs=4096
```

### 5.4 Monitor with TensorBoard

Open a **second terminal** on the Brev host while training runs:

```bash
docker exec tienkung \
    /workspace/isaaclab/isaaclab.sh -p -m tensorboard.main \
    --logdir /workspace/TienKung-Lab/logs --host 0.0.0.0 --port 6006
```

Open `http://<brev-instance-ip>:6006` in a browser.
(Port 6006 is already mapped in the compose file.)

### 5.5 Interactive shell (for debugging or one-off commands)

```bash
docker exec -it tienkung bash
# inside the container:
conda activate isaaclab   # if needed
cd /workspace/TienKung-Lab
```

---

## Phase 6 — Policy Playback and Video Recording

### How the video recorder works

Isaac Sim includes an offscreen GPU renderer. Passing `--headless --video` to `play.py`
activates it: Isaac Sim renders frames to a GPU framebuffer, encodes them to MP4, and
writes the file to the `videos/` directory. No display or browser tab is needed.

Videos are written to `~/results/videos/` on the Brev host (bind-mounted into the container at
`/workspace/TienKung-Lab/videos/`). Download with `rsync` — no export step needed.

### 6.1 Record Walk Policy Playback

```bash
# Using the latest training checkpoint
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play.py \
    --task=walk --num_envs=1 \
    --headless --video --video_length 500 \
    --checkpoint logs/walk/<timestamp>/model_<iter>.pt

# Using the pre-trained policy bundled in the repo
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play.py \
    --task=walk --num_envs=1 \
    --headless --video --video_length 500 \
    --checkpoint Exported_policy/walk.pt
```

Output: `~/results/videos/walk_<timestamp>.mp4`

### 6.2 Record AMP Motion Visualization (quality check)

Verify the GMR retargeting result before or after training:
```bash
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play_amp_animation.py \
    --task=walk --num_envs=1 \
    --headless --video --video_length 300
```

Output: `~/results/videos/walk_amp_<timestamp>.mp4`

> **If `--video` flag is not supported by TienKung's `play.py`:**
> Isaac Lab's `play.py` scripts may not expose `--video` directly. In that case, wrap
> the environment with `gym.wrappers.RecordVideo`:
> ```python
> # Add after env creation in play.py:
> import gymnasium as gym
> env = gym.wrappers.RecordVideo(
>     env, video_folder="videos/", episode_trigger=lambda ep: True
> )
> ```
> Or use Isaac Lab's native `--enable_cameras` + `--video` flags if available in 2.1.0.

### 6.3 Sim2Sim Transfer (MuJoCo)

`play.py` auto-exports the policy to `logs/.../exported/policy.pt` after playback.

```bash
# Using latest exported policy
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/sim2sim.py \
    --task walk \
    --policy logs/walk/<timestamp>/exported/policy.pt \
    --duration 100

# Using pre-trained policy
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/sim2sim.py \
    --task walk \
    --policy Exported_policy/walk.pt \
    --duration 100
```

---

## Results Directory

All intermediate and final outputs land in `~/results/` on the Brev host — user-owned
bind mounts, directly browsable and rsync-able without any export step.

```
~/results/
├── gmr/         GMR retargeting output (.pkl + any motion visualizations)
├── logs/        training checkpoints + TensorBoard event files
├── videos/      recorded MP4 policy playbacks
└── datasets/    AMP expert motion data (motion_visualization/, motion_amp_expert/)
```

### Output location summary

| What | Host path | Survives `compose down`? | Survives VM deletion? |
|------|-----------|-------------------------|-----------------------|
| GMR retargeting output | `~/results/gmr/` | ✅ Yes | ❌ No — rsync before deleting |
| Training checkpoints | `~/results/logs/` | ✅ Yes | ❌ No — rsync before deleting |
| Policy videos (MP4) | `~/results/videos/` | ✅ Yes | ❌ No — rsync before deleting |
| AMP motion datasets | `~/results/datasets/` | ✅ Yes | ❌ No — rsync before deleting |
| Isaac Sim shader cache | Named volume `tienkung-shader-cache` | ✅ Yes | ❌ No (not needed) |
| AMASS input data | `~/data/amass/` | ✅ Yes | ❌ No — re-download if needed |
| Source code | `~/TienKung-Lab/` | ✅ Yes | ❌ No |

> **Rule of thumb:** Stop the Brev instance (**not delete**) between sessions.
> Before deleting the instance, rsync `~/results/` to your local machine.

---

## Retrieving Results

All outputs are in `~/results/` on the Brev host — user-owned bind mounts,
no export step required.

### Download to your local machine

Run from **your local machine** (replace `<brev-ip>` with the Brev dashboard IP):

```bash
# Download everything at once
rsync -avz --progress ubuntu@<brev-ip>:~/results/ ./results/

# Cherry-pick: just checkpoints
rsync -avz ubuntu@<brev-ip>:~/results/logs/ ./results/logs/

# Cherry-pick: just videos
rsync -avz ubuntu@<brev-ip>:~/results/videos/ ./results/videos/

# Cherry-pick: exported policy only
scp ubuntu@<brev-ip>:~/results/logs/walk/*/exported/policy.pt ./policy.pt
```

### One-shot archive — before deleting the Brev instance

Run on the **Brev VM**:

```bash
tar czf ~/tienkung-backup-$(date +%Y%m%d).tar.gz ~/results/
ls -lh ~/tienkung-backup-*.tar.gz

# Download from your local machine
scp ubuntu@<brev-ip>:~/tienkung-backup-*.tar.gz ./
```

### Upload to S3 (optional)

```bash
pip install awscli
aws s3 sync ~/results/ s3://<your-bucket>/tienkung/results/
```
