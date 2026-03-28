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
