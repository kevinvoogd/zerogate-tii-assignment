# Installation

Provision the Brev VM, log in to NGC, and build the Docker image.

---

## Phase 1 — Brev VM Setup and Docker Image Build

### 1.1 Create a Brev Instance

1. Log in at https://brev.nvidia.com → **Launchables → Create Launchable**
2. Choose **VM Mode — Basic VM with Python installed**
3. Paste the contents of `setup_script.sh` as the setup script
4. Choose a GPU instance ≥ 24 GB VRAM (e.g. AWS g6e.4xlarge — L40S GPU)
5. Set disk ≥ **300 GB** (Isaac Sim base image alone is ~15 GB)
6. Open ports: **6006** (TensorBoard), **8211** (web viewer), **49100** (WebRTC signaling), **47998** (WebRTC media)

### 1.2 Build the web-viewer image

The `web-viewer` container serves a browser UI for WebRTC livestreaming.
Build it alongside the main image:

```bash
cd ~/assignment_tii
docker compose build web-viewer
```

### 1.3 Verify `setup_script.sh` completed (auto-runs on first boot)

`setup_script.sh` runs automatically on first boot and does all of the following:
- Clones `assignment_tii`, `TienKung-Lab`, and `GMR`
- Creates `~/data/`, `~/results/` directories
- Installs Miniconda + creates the `gmr` conda env
- Applies the SMPLX `.npz` → `.pkl` extension fix
- Logs in to NGC (`org.ngc.nvidia.com`) and builds the Docker image (`NGC_API_KEY` must be set)

Verify everything completed:

```bash
conda env list                        # must show 'gmr'
ls ~/data/ ~/results/                 # both must exist
ls ~/TienKung-Lab/                    # must show the cloned repo
docker images | grep tienkung         # must show tienkung-isaaclab:2.1.0
```

### 1.3 If the Docker image is missing (NGC_API_KEY was not set at boot)

`setup_script.sh` skips the NGC login and build if `NGC_API_KEY` is not set.
If `docker images | grep tienkung` shows nothing, run manually:

```bash
export NGC_API_KEY=<your key from https://org.ngc.nvidia.com/setup/api-key>

# Non-interactive (scripting / CI)
echo "$NGC_API_KEY" | docker login nvcr.io \
    --username '$oauthtoken' --password-stdin

# Interactive (manual login in a terminal)
# docker login nvcr.io
#   Username: $oauthtoken          ← literal string, not a shell variable
#   Password: <paste key here>

docker build -t tienkung-isaaclab:2.1.0 ~/assignment_tii/
# First build: ~20–40 min. Subsequent builds use cache.
```

> **If `isaac-lab:2.1.0` is not on NGC:** uncomment the fallback block in `Dockerfile`
> (builds Isaac Lab from source on top of `isaac-sim:4.5.0`).

> **Username note:** `$oauthtoken` is a fixed literal string used by all NGC users —
> it is not a shell variable. Always quote it (`'$oauthtoken'`) or escape the `$`
> when passing on the command line to prevent shell expansion.

### 1.4 Verify the image

```bash
docker run --gpus all --rm tienkung-isaaclab:2.1.0 \
    /workspace/isaaclab/isaaclab.sh -p -c \
    "import legged_lab; print('TienKung-Lab OK')"
```
