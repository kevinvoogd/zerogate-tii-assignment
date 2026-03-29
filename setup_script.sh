#!/bin/bash
# =============================================================================
# Brev VM Bootstrap — TienKung (Dockerized, headless) - Runs automatically on first boot when pasted into Brev's setup script field.
#
# What this script does:
#   1. Clones this assignment repo (Dockerfile + docker-compose)
#   2. Clones TienKung-Lab (source for bind-mount + live editing)
#   3. Clones GMR and installs it in a dedicated 'gmr' conda env on the host
#   4. Creates ~/data/{amass,smplx} directories
#   5. Applies the required SMPLX extension fix in GMR
#   6. Logs in to NGC (if NGC_API_KEY env var is set) and builds the image
#
# Before creating the Brev instance, set the following environment variable
# in Brev's "Environment Variables" panel (or export before re-running):
#
#   NGC_API_KEY=<your key from https://ngc.nvidia.com/setup/api-key>
#
# TienKung and RSL_RL are installed INSIDE the image (Dockerfile).
# No pip install is performed on the host or inside a running container here.
# =============================================================================
set -euo pipefail

# Auto-accept Anaconda TOS in non-interactive environments (e.g. Brev setup scripts)
export CONDA_PLUGINS_AUTO_ACCEPT_TOS=true

# ── Variables ────────────────────────────────────────────────────────────────
HOME_DIR="/home/ubuntu"
ASSIGNMENT_DIR="$HOME_DIR/zerogate-tii-assignment"
ASSIGNMENT_REPO="https://github.com/kevinvoogd/zerogate-tii-assignment.git"
TIENKUNG_DIR="$HOME_DIR/TienKung-Lab"
GMR_DIR="$HOME_DIR/GMR"
DATA_DIR="$HOME_DIR/data"
IMAGE_TAG="tienkung-isaaclab:2.1.0"

# NGC_API_KEY is expected from the environment (set in Brev's env vars panel).
NGC_API_KEY="${NGC_API_KEY:-}"  # reads from environment; empty string = skip NGC steps

# ── 1. Clone repos ───────────────────────────────────────────────────────────
cd "$HOME_DIR"

if [[ ! -d "$ASSIGNMENT_DIR/.git" ]]; then
    git clone "$ASSIGNMENT_REPO" "$ASSIGNMENT_DIR"
else
    echo "zerogate-tii-assignment already cloned — skipping."
fi

if [[ ! -d "$TIENKUNG_DIR/.git" ]]; then
    git clone https://github.com/Open-X-Humanoid/TienKung-Lab "$TIENKUNG_DIR"
else
    echo "TienKung-Lab already cloned — skipping."
fi

if [[ ! -d "$GMR_DIR/.git" ]]; then
    git clone https://github.com/YanjieZe/GMR "$GMR_DIR"
else
    echo "GMR already cloned — skipping."
fi

# ── 2. Create data directories ───────────────────────────────────────────────
mkdir -p "$DATA_DIR/amass" "$DATA_DIR/smplx"
echo "Data directories ready: $DATA_DIR/{amass,smplx}"

mkdir -p "$HOME_DIR/results/gmr" "$HOME_DIR/results/logs" \
         "$HOME_DIR/results/videos" "$HOME_DIR/results/datasets"
echo "Results directories ready: ~/results/{gmr,logs,videos,datasets}"

# ── 3. Install Miniconda (if absent) and create GMR conda env ────────────────
# GMR runs on the host VM (not inside the container) to avoid dependency
# conflicts with Isaac Lab. Its output PKL is written to $DATA_DIR and
# bind-mounted into the container as /workspace/data.

if ! command -v conda &>/dev/null; then
    echo "Installing Miniconda..."
    curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
        -o /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p "$HOME_DIR/miniconda3"
    eval "$("$HOME_DIR/miniconda3/bin/conda" shell.bash hook)"
    conda init bash
fi

eval "$(conda shell.bash hook)"

if ! conda env list | grep -q '^gmr '; then
    conda create -n gmr python=3.10 -y
fi

conda activate gmr
pip install -e "$GMR_DIR"

# ── 4. Apply SMPLX extension fix ─────────────────────────────────────────────
# The smplx package (installed in the gmr conda env) defaults to looking for
# .npz body model files, but the SMPL-X website ships .pkl files.
SMPLX_MODELS="$HOME_DIR/miniconda3/envs/gmr/lib/python3.10/site-packages/smplx/body_models.py"
if [[ -f "$SMPLX_MODELS" ]]; then
    sed -i "s/ext: str = 'npz'/ext: str = 'pkl'/" "$SMPLX_MODELS"
    echo "SMPLX extension fix applied: $SMPLX_MODELS"
else
    echo "WARNING: $SMPLX_MODELS not found — skipping SMPLX fix."
    echo "         Run manually after setup: see README.md Phase 2.5"
fi

# ── 5. Install display utilities (needed for X11 forwarding + xvfb) ────────────
sudo apt-get install -y --no-install-recommends xvfb x11-utils x11-apps

# ── 6. NGC login and Docker image build ──────────────────────────────────────
if [[ -z "$NGC_API_KEY" ]]; then
    echo ""
    echo "WARNING: NGC_API_KEY is not set."
else
    echo "Logging in to NGC..."
    echo "$NGC_API_KEY" | docker login nvcr.io \
        --username '$oauthtoken' \
        --password-stdin

    echo "Building Docker image $IMAGE_TAG (this takes 20-40 min on first run)..."
    docker build -t "$IMAGE_TAG" "$ASSIGNMENT_DIR"
    echo "Image build complete: $IMAGE_TAG"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "====================================================================="
echo " Brev VM setup complete."
echo " Next steps (see README.md for full details):"
echo ""
echo "  1. Download AMASS data into: $DATA_DIR/amass/"
echo "     (requires free account at https://amass.is.tue.mpg.de/)"
echo ""
if [[ -z "$NGC_API_KEY" ]]; then
echo "  2. Set NGC_API_KEY, then build the Docker image:"
echo "       export NGC_API_KEY=<your key>"
echo "       echo \"\$NGC_API_KEY\" | docker login nvcr.io -u '\$oauthtoken' --password-stdin"
echo "       docker build -t $IMAGE_TAG $ASSIGNMENT_DIR"
echo ""
fi
echo "  3. Start the persistent container:"
echo "       docker compose up -d"
echo ""
echo "  4. Run GMR retargeting on the host:"
echo "       conda activate gmr"
echo "       cd $GMR_DIR"
echo "       python scripts/smplx_to_robot.py --robot tienkung ..."
echo "====================================================================="