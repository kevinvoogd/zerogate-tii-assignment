# Troubleshooting & Quick Reference

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `docker build` fails: `manifest not found` | `isaac-lab:2.1.0` not on NGC | Uncomment the fallback block in `Dockerfile` (build from source on `isaac-sim:4.5.0`) |
| `docker login nvcr.io` rejected | Wrong credentials | Username must be literally `$oauthtoken`; password is the NGC API key |
| `ModuleNotFoundError: legged_lab` | Source volume mount shadowed baked-in install | Run `docker run ... /workspace/isaaclab/isaaclab.sh -p -m pip install -e /workspace/TienKung-Lab` |
| Isaac Lab API import errors (e.g. `ArticulationCfg`) | IL 2.1 → 2.2 breaking changes | Check [IL 2.2 changelog](https://isaac-sim.github.io/IsaacLab/main/source/refs/changelog.html); patch the affected symbols in TienKung source |
| GMR `KeyError` on SMPLX data | Wrong ext setting | `sed -i "s/ext: str = 'npz'/ext: str = 'pkl'/" ~/miniconda3/envs/gmr/lib/python3.10/site-packages/smplx/body_models.py` |
| GMR `--record_video` produces no video / display error | No X display on headless Brev host | Prefix with `MUJOCO_GL=egl`; fallback: install osmesa and use `MUJOCO_GL=osmesa` (see Phase 3.1) |
| `play_amp_animation.py` crashes: `RuntimeError: operator torchvision::nms does not exist` | Dockerfile extension-disable was malformed (wrong TOML syntax); `isaaclab_tasks` loads and crashes | Rebuild the image — the Dockerfile now patches `stack_ik_rel_blueprint_env_cfg.py` and disables the extension with correct TOML |
| `Warp CUDA error 36: cuDeviceGetUuid not found` | vGPU/GRID instance restricts some CUDA profiling APIs | Non-fatal — Warp falls back to CPU; `cap_add: SYS_PTRACE` in docker-compose.yml allows the UUID lookup and silences the error |
| `failed to open the default display` in `play_amp_animation.py` log | Headless VM, no X server | Expected with `--headless`; Isaac Sim renders offscreen — this warning does not affect video recording |
| `--video` flag not recognised by `play_amp_animation.py` | Flag availability varies across IL builds | Wrap with `gym.wrappers.RecordVideo` (see Phase 6.2 in [training.md](training.md)) |
| No video output file after `play_amp_animation.py` | Wrong output path | Videos write to `/workspace/TienKung-Lab/videos/` → `~/results/videos/`; confirm with `ls -lh ~/results/videos/` |
| TensorBoard port unreachable | Brev security group | Open port 6006 in the Brev instance network settings |
| Reward does not converge | Too few envs or bad AMP data | Increase `--num_envs`; verify motion quality with AMP visualization first (Phase 6.2) |

---

## Interactive Visualization via X11 Forwarding

If you want a **live Isaac Sim window** on your laptop screen instead of downloading an MP4:

### Step 1 — SSH with X11 forwarding

```bash
# From your local machine:
ssh -X ubuntu@<brev-ip>

# Confirm DISPLAY is set:
echo $DISPLAY   # e.g. localhost:10.0
```

> macOS users: install [XQuartz](https://www.xquartz.org/) first and use `ssh -X`.

### Step 2 — Copy the auth token into the container

```bash
# On the Brev host, get your X auth entry:
xauth list $DISPLAY
# Output: <host>/unix:10  MIT-MAGIC-COOKIE-1  <hex-token>

# Pass DISPLAY and the X11 socket into the container, add the auth token:
docker exec \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    tienkung bash -c "
        xauth add $(xauth list $DISPLAY) && \
        cd /workspace/TienKung-Lab && \
        /workspace/isaaclab/isaaclab.sh -p \
            legged_lab/scripts/play_amp_animation.py \
            --task=walk --num_envs=1"
# Repeat with --task=run for the run motion.
```

Isaac Sim renders on the Brev GPU; the window is forwarded to your laptop over SSH.

> **Latency note**: X11 forwarding over SSH can feel sluggish for real-time 3D rendering.
> The MP4 approach (Phase 6.2) is better for detailed quality review; use X11 when you
> need interactive control (e.g. to orbit the camera).

---

## Quick Reference: Key Commands

```bash
# ── Build ─────────────────────────────────────────────────────────────────
docker login nvcr.io          # username: $oauthtoken  password: <NGC key>
docker build -t tienkung-isaaclab:2.1.0 ~/assignment_tii/

# ── Container lifecycle ──────────────────────────────────────────────────
docker compose up -d     # start
docker compose down       # stop (volumes PRESERVED)
docker compose down -v    # stop + DELETE ALL VOLUMES
docker exec -it tienkung bash                            # interactive shell

# ── GMR retargeting (on host, gmr conda env) ─────────────────────────────
conda activate gmr && cd ~/GMR
# Single file (with video for intermediate result):
python scripts/smplx_to_robot.py \
    --smplx_file ~/data/amass/CMU/01/01_01_poses.npz \
    --robot tienkung \
    --save_path ~/results/gmr/tienkung_walk.pkl \
    --record_video --video_path ~/results/gmr/walk_retarget.mp4
# Batch (recurses all subfolders of src automatically):
python scripts/smplx_to_robot_dataset.py \
    --src_folder ~/data/amass/CMU/ \
    --tgt_folder ~/results/gmr/ \
    --robot tienkung --num_cpus 4

# ── Data processing (Phase 4) ────────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/gmr_data_conversion.py \
    --input_pkl /workspace/results/gmr/tienkung_motion.pkl \
    --output_txt legged_lab/envs/tienkung/datasets/motion_visualization/motion.txt

# ── Training ─────────────────────────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/train.py \
    --task=walk --headless --logger=tensorboard --num_envs=4096

# ── TensorBoard (second terminal, container already running) ──────────────
docker exec tienkung \
    /workspace/isaaclab/isaaclab.sh -p -m tensorboard.main \
    --logdir /workspace/TienKung-Lab/logs --host 0.0.0.0 --port 6006
# open http://<brev-ip>:6006

# ── Playback + video recording ────────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play.py \
    --task=walk --num_envs=1 --headless --video --video_length 500 \
    --checkpoint Exported_policy/walk.pt
# videos written to ~/results/videos/

# ── Check results on Brev host ────────────────────────────────────────────
ls -lhR ~/results/

# ── Download to local machine (run from your local PC) ───────────────────
rsync -avz --progress ubuntu@<brev-ip>:~/results/ ./results/

# ── Sim2Sim ───────────────────────────────────────────────────────────────
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/sim2sim.py \
    --task walk --policy Exported_policy/walk.pt --duration 100
```
