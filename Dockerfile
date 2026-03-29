# =============================================================================
# TienKung-Lab + Isaac Lab 2.1.0 
#
# Strategy: headless training + Isaac Sim built-in video recorder for playback.
# No browser viewer needed. Checkpoints and videos are written to host via volumes.
#
# Prerequisites:
#   docker login nvcr.io
#     Username: $oauthtoken
#     Password: <NGC API key from https://ngc.nvidia.com/setup/api-key>
#
# Build:
#   docker build -t tienkung-isaaclab:2.1.0 .
#
# First build: ~20-40 min (pulls ~15 GB Isaac Sim base layer).
# Subsequent builds: fast (cached).
FROM nvcr.io/nvidia/isaac-lab:2.1.0

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 \
        https://github.com/Open-X-Humanoid/TienKung-Lab \
        /workspace/TienKung-Lab

# Install TienKung-Lab and RSL_RL using Isaac Lab's managed Python
RUN /workspace/isaaclab/isaaclab.sh -p -m pip install -e /workspace/TienKung-Lab
RUN /workspace/isaaclab/isaaclab.sh -p -m pip install -e /workspace/TienKung-Lab/rsl_rl

# ---------------------------------------------------------------------------
# Disable isaaclab_tasks extension — it fails to load because the extscache
# torchvision (omni.isaac.ml_archive-2.1.2) was built against a different
# PyTorch than the one bundled in Isaac Lab's Python, causing:
#   RuntimeError: operator torchvision::nms does not exist
# TienKung only uses legged_lab; isaaclab_tasks is never needed.
# Without this fix, play_amp_animation.py crashes during AppLauncher startup.
#
# Fix 1 (surgical) — wrap the offending import so the extension loads with a
# warning instead of raising and killing the whole AppLauncher.
# ---------------------------------------------------------------------------
RUN python3 -c "
import pathlib
f = pathlib.Path('/workspace/isaaclab/source/isaaclab_tasks/isaaclab_tasks/manager_based/manipulation/stack/config/franka/stack_ik_rel_blueprint_env_cfg.py')
if f.exists():
    src = f.read_text()
    old = 'from torchvision.utils import save_image'
    new = 'try:\n    from torchvision.utils import save_image\nexcept Exception:\n    save_image = None  # IL 2.1 extscache torchvision/torch mismatch'
    if old in src and new not in src:
        f.write_text(src.replace(old, new))
        print('patched stack_ik_rel_blueprint_env_cfg.py')
    else:
        print('already patched or file changed — skipping')
" || true

# Fix 2 (belt-and-suspenders) — append valid TOML to every kit app config that
# exists so the extension is also disabled at the extension-manager level.
RUN for KIT in \
        /workspace/isaaclab/apps/isaaclab.python.headless.kit \
        /workspace/isaaclab/apps/isaaclab.python.headless.rendering.kit \
        /workspace/isaaclab/apps/isaaclab.python.kit; do \
    [ -f "$KIT" ] && printf '\n[settings]\nexts."omni.isaac.lab_tasks".enabled = false\n' >> "$KIT" && echo "disabled isaaclab_tasks in $KIT"; \
    done || true

# ---------------------------------------------------------------------------
# Output directories (will be bind-mounted from host — created here as targets)
# ---------------------------------------------------------------------------
RUN mkdir -p \
    /workspace/TienKung-Lab/logs \
    /workspace/TienKung-Lab/videos \
    /workspace/data

WORKDIR /workspace/TienKung-Lab

# ---------------------------------------------------------------------------
# Default command: headless walk training
# Override at runtime via `docker run ... <command>` or in docker-compose.
# ---------------------------------------------------------------------------
CMD ["/workspace/isaaclab/isaaclab.sh", "-p", \
     "legged_lab/scripts/train.py", \
     "--task=walk", "--headless", "--logger=tensorboard", "--num_envs=4096"]
