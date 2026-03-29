# Data Preparation

Download AMASS motion capture data, retarget it to the TienKung robot with GMR, then
convert the output for use inside the training container.

---

## Phase 2 — Download AMASS Data (Manual, One-Time)

AMASS provides SMPLX motion capture sequences used as AMP reference motions.

### 2.1 Register

| Resource | URL |
|----------|-----|
| AMASS dataset | https://amass.is.tue.mpg.de/ |
| SMPL-X models | https://smplx.is.tue.mpg.de/ |

### 2.2 Prune and Transfer AMASS Data

The full CMU archive contains ~2400 clips (uneven terrain, stylised walks, social
interactions…). `prune_amass_cmu.sh` extracts the archive and immediately deletes
every `.npz` not listed in `scripts/motion_tasks.csv`, cutting the transfer to only
the walk/run clips that will actually be used.

**Step 1 — Clone this repo on your local PC** (if not already done):
```bash
git clone <this-repo-url> ~/assignment_tii
```

**Step 2 — Prune the archives** (run on your local PC):
```bash
chmod +x ~/assignment_tii/scripts/prune_amass_cmu.sh

# Pass the directory containing CMU.bz2 and HumanEva.tar.bz2
~/assignment_tii/scripts/prune_amass_cmu.sh /assignment_data/amass/
# Outputs: /assignment_data/amass/CMU/       (pruned)
#          /assignment_data/amass/HumanEva/  (pruned)
#          /assignment_data/amass/CMU_reduced.tar.bz2
#          /assignment_data/amass/HumanEva_reduced.tar.bz2
```

Expected output:
```
Manifest loaded: 316 listed clips.
Pruning CMU ...
  Kept: 207  |  Deleted: 1776  |  Empty dirs removed.
  Written: .../CMU_reduced.tar.bz2  (~XMB)

Pruning HumanEva ...
  Kept: 9  |  Deleted: 21  |  Empty dirs removed.
  Written: .../HumanEva_reduced.tar.bz2  (~XMB)
````

**Step 3 — Transfer to Brev** (run on your local PC; replace `<brev-ip>`):

> **rsync vs scp** — always use `rsync`: it is resumable, skips already-transferred
> files on re-run, and shows transfer speed. `scp` restarts from scratch on failure.

```bash
# SMPL-X body model zip (one-time, ~300 MB)
rsync -avz --progress ~/Downloads/models_smplx_v1_1.zip ubuntu@<brev-ip>:~/

# Pruned datasets (walk/run clips only)
rsync -avz --progress /assignment_data/amass/CMU/      ubuntu@<brev-ip>:~/data/amass/CMU/
rsync -avz --progress /assignment_data/amass/HumanEva/ ubuntu@<brev-ip>:~/data/amass/HumanEva/
```

### 2.3 Extract SMPL-X Body Models (on Brev host)

The body model path is **hardcoded** in GMR — files must land at:
```
~/GMR/assets/body_models/smplx/SMPLX_NEUTRAL.pkl
~/GMR/assets/body_models/smplx/SMPLX_MALE.pkl
~/GMR/assets/body_models/smplx/SMPLX_FEMALE.pkl
```

Download **SMPL-X v1.1** from https://smplx.is.tue.mpg.de/ (one zip with all three genders).

```bash
# Check zip structure first — it often wraps files inside models/smplx/
unzip -l ~/models_smplx_v1_1.zip | head -20

mkdir -p ~/GMR/assets/body_models/smplx

# Extract (adjust inner path if the zip structure differs)
unzip ~/models_smplx_v1_1.zip -d /tmp/smplx_extract
mv /tmp/smplx_extract/models/smplx/*.pkl ~/GMR/assets/body_models/smplx/
rm -rf /tmp/smplx_extract

# Verify
ls ~/GMR/assets/body_models/smplx/
# must show: SMPLX_NEUTRAL.pkl  SMPLX_MALE.pkl  SMPLX_FEMALE.pkl
```

### 2.4 Verify AMASS Data on Brev Host

After the rsync in step 2.2 completes, confirm the pruned clips landed correctly:

```bash
# Should show only subject directories that are in motion_tasks.csv
ls ~/data/amass/CMU/

# Spot-check a run subject (09) and a walk subject (07)
ls ~/data/amass/CMU/09/    # expect 09_01_stageii.npz … 09_12_stageii.npz
ls ~/data/amass/CMU/07/    # expect 07_01_stageii.npz … 07_12_stageii.npz

# Total clip count — should match ~310
find ~/data/amass/CMU -name '*_poses.npz' | wc -l
```

> **AMASS data and GMR output paths are freely chosen** — only the body model location
> is fixed. Pass your AMASS path via `--smplx_file` / `--src_folder`.

### 2.5 Fix SMPLX `.npz` vs `.pkl` Extension

The `smplx` Python package (installed inside the `gmr` conda env) defaults to looking
for `.npz` body model files, but the SMPL-X website ships `.pkl` files.
The fix targets the **site-packages install**, not the GMR repo clone:

```bash
sed -i "s/ext: str = 'npz'/ext: str = 'pkl'/" \
    ~/miniconda3/envs/gmr/lib/python3.10/site-packages/smplx/body_models.py
```

(`setup_script.sh` runs this automatically — only needed if you skipped the setup script.)

---

## Phase 3 — GMR Retargeting (Brev Host, `gmr` conda env)

GMR runs on the **host**, not inside Docker. Output is saved to `~/results/gmr/`
which is bind-mounted into the container as `/workspace/results/gmr`.

### 3.1 Single file — verify + save visualization (required intermediate result)

Run on one file first to confirm the retargeting looks correct and record the video:

```bash
conda activate gmr
cd ~/GMR

# On the headless Brev VM, MuJoCo needs an offscreen GL backend.
# MUJOCO_GL=egl works on all Brev NVIDIA GPU instances (no display required).
MUJOCO_GL=egl python scripts/smplx_to_robot.py \
    --smplx_file ~/data/amass/CMU/01/01_01_poses.npz \
    --robot tienkung \
    --save_path ~/results/gmr/tienkung_walk.pkl \
    --record_video --video_path ~/results/gmr/walk_retarget.mp4
```

Saves the MP4 to `~/results/gmr/` without needing a display.
The `.mp4` is the **intermediate result** for the motion retargeting stage.

> **If EGL is unavailable** (error: `Failed to initialize OpenGL`), install osmesa and use the software renderer:
> ```bash
> sudo apt-get install -y libosmesa6-dev
> MUJOCO_GL=osmesa python scripts/smplx_to_robot.py \
>     --smplx_file ~/data/amass/CMU/01/01_01_poses.npz \
>     --robot tienkung \
>     --save_path ~/results/gmr/tienkung_walk.pkl \
>     --record_video --video_path ~/results/gmr/walk_retarget.mp4
> ```
>
> Download to your local machine to view:
> ```bash
> rsync -avz ubuntu@<brev-ip>:~/results/gmr/walk_retarget.mp4 ./
> ```

### 3.2 Batch — whole dataset folder at once

`smplx_to_robot_dataset.py` uses `os.walk()` internally — it **recurses into all
subdirectories automatically**. Pointing `--src_folder` at `~/data/amass/CMU/` will
process `01/`, `02/`, `03/`, `04/` ... in one command, mirroring the source folder
structure under `--tgt_folder`:

```
~/data/amass/CMU/01/01_01_poses.npz  →  ~/results/gmr/01/01_01_poses.pkl
~/data/amass/CMU/01/01_02_poses.npz  →  ~/results/gmr/01/01_02_poses.pkl
~/data/amass/CMU/02/02_01_poses.npz  →  ~/results/gmr/02/02_01_poses.pkl
...
```

```bash
python scripts/smplx_to_robot_dataset.py \
    --src_folder ~/data/amass/CMU/ \
    --tgt_folder ~/results/gmr/ \
    --robot tienkung \
    --num_cpus 4
```

- **Re-run safe** — already-processed `.pkl` files are skipped (add `--override` to force redo)
- **Auto-excludes** known hard/infeasible motions (crawl, lie, stairs, etc.)
- **No visualization** in batch mode by default

Verify:
```bash
ls -lh ~/results/gmr/tienkung_walk.pkl   # single-file output
ls -lhR ~/results/gmr/                   # batch output tree
```

> For training, Phase 4 data conversion takes a single `.pkl`.
> - **Single clip (quickstart):** use the single-file output from 3.1 and pass it to Phase 4 once.
> - **Full dataset:** run the Phase 4 loop below — `motion_loader.py` loads every `.txt` in
>   `motion_amp_expert/` automatically via `glob.glob`, so no config change is needed once the
>   folder is populated.

---

## Phase 4 — Data Processing (Inside Container)

Start the container first if it isn't already running:
```bash
docker compose up -d
```

### 4.0 Create the motion-task manifest

`motion_tasks.csv` maps each CMU subject/trial to its Isaac Lab task (`walk` or `run`).
**Only clips in this file are processed.** Any retargeted `.pkl` not listed here is
skipped — this prevents stylised, backward, sideways, or interaction motions from
contaminating the AMP reference dataset.

The selection keeps:
- **walk** — straight forward walks, turns, and pace variations from clean subjects
- **run** — forward runs and jogs; includes obstacle-course runs (subjects 127–128) for
  motion diversity

Excluded (not listed): uneven terrain, emotional/stylised walks, backward walks,
sideways walks, social-interaction clips, and vignette subjects (56, 86).

The manifest file is committed to this repo at `scripts/motion_tasks.csv`.
Run this **once** on the Brev host to copy it into place:

```bash
# setup_script.sh cloned this repo to ~/assignment_tii
cp ~/assignment_tii/scripts/motion_tasks.csv ~/results/gmr/motion_tasks.csv
```

Verify:
```bash
grep -c ,walk ~/results/gmr/motion_tasks.csv   # ~169 walk entries
grep -c ,run  ~/results/gmr/motion_tasks.csv   # ~141 run entries
head -3 ~/results/gmr/motion_tasks.csv         # subject,trial,task / 02,01,walk / 02,02,walk
```

> **Editing the manifest:** subject values must match the GMR output folder name exactly
> — zero-padded 2-digit for subjects < 100 (e.g. `09`), no padding for ≥ 100 (e.g. `127`).
> Trial values must match the second `_`-separated field of the filename (always 2-digit,
> e.g. `01`, `35`). Any clip **not listed** is silently skipped — add it here first if you
> want it processed. The source of truth is `scripts/motion_tasks.csv` in this repo;
> edit that file and re-run the `cp` command to update the Brev copy.

---

### 4.1 Single clip (quickstart)

Convert one `.pkl` and generate its AMP expert file:

```bash
# Step A — convert to visualization format
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/gmr_data_conversion.py \
    --input_pkl /workspace/results/gmr/tienkung_walk.pkl \
    --output_txt legged_lab/envs/tienkung/datasets/motion_visualization/walk.txt

# Step B — generate AMP expert data
docker exec -w /workspace/TienKung-Lab tienkung \
    /workspace/isaaclab/isaaclab.sh -p \
    legged_lab/scripts/play_amp_animation.py \
    --task=walk --num_envs=1 \
    --headless \
    --save_path legged_lab/envs/tienkung/datasets/motion_amp_expert/walk.txt \
    --fps 30.0
```

Then update the walk task config:
- `amp_motion_files_display` → `legged_lab/envs/tienkung/datasets/motion_visualization/walk.txt`
- `amp_motion_files` → `legged_lab/envs/tienkung/datasets/motion_amp_expert/walk.txt`

---

### 4.2 Full dataset (all retargeted clips)

`motion_loader.py` loads **every `.txt` file** in `datasets/motion_amp_expert/` via
`glob.glob` — no config change needed once the folder is populated.

Run a loop on the Brev host. The helper `get_task` looks up each clip in
`motion_tasks.csv` and returns its task, or an empty string if not listed.
Unlisted clips are **skipped** — they will not be passed to Isaac Sim.

Before committing the full run (each clip launches Isaac Sim), do a **dry-run** to
verify task assignment:

```bash
MANIFEST=~/results/gmr/motion_tasks.csv

# CMU subjects are numeric ("09"); HumanEva subjects are alpha ("S1").
# CMU trial  = 2nd _-field of filename stem  e.g. "09_01" → "01"
# HumanEva trial = full filename stem        e.g. "Walking_3"
get_trial() {
    local subj="$1" fname="$2"
    if [[ "$subj" =~ ^[0-9]+$ ]]; then
        echo "$fname" | cut -d_ -f2
    else
        echo "$fname"
    fi
}

get_task() {
    awk -F, -v s="$1" -v t="$2" '$1==s && $2==t {print $3}' "$MANIFEST"
}

for pkl in $(find ~/results/gmr -name '*.pkl'); do
    subject=$(basename "$(dirname "$pkl")")
    fname=$(basename "$pkl" _stageii.pkl)
    trial=$(get_trial "$subject" "$fname")
    TASK=$(get_task "$subject" "$trial")
    if [[ -z "$TASK" ]]; then
        echo "Skip [unlisted]: $pkl"
    else
        echo "${TASK}  $pkl"
    fi
done
```

Once the assignments look correct, run the full loop:

```bash
# Run from the Brev host (not inside the container)
MANIFEST=~/results/gmr/motion_tasks.csv

get_trial() {
    local subj="$1" fname="$2"
    if [[ "$subj" =~ ^[0-9]+$ ]]; then
        echo "$fname" | cut -d_ -f2
    else
        echo "$fname"
    fi
}

get_task() {
    awk -F, -v s="$1" -v t="$2" '$1==s && $2==t {print $3}' "$MANIFEST"
}

for pkl in $(find ~/results/gmr -name '*.pkl'); do
    rel="${pkl#$HOME/results/gmr/}"          # e.g. 09/09_01_stageii.pkl
    base="${rel//\//_}"                      # e.g. 09_09_01_stageii
    base="${base%.pkl}"

    subject=$(basename "$(dirname "$pkl")")  # e.g. "09", "S1"
    fname=$(basename "$pkl" _stageii.pkl)   # e.g. "09_01", "Walking_3"
    trial=$(get_trial "$subject" "$fname")  # e.g. "01", "Walking_3"
    TASK=$(get_task "$subject" "$trial")    # "walk", "run", or empty

    # Skip clips not listed in the manifest
    [[ -z "$TASK" ]] && { echo "Skip [unlisted]: ${base}"; continue; }

    # Ensure output directories exist inside the container
    docker exec tienkung mkdir -p \
        /workspace/TienKung-Lab/legged_lab/envs/tienkung/datasets/motion_visualization \
        /workspace/TienKung-Lab/legged_lab/envs/tienkung/datasets/motion_amp_expert

    # Step A — visualization format
    docker exec -w /workspace/TienKung-Lab tienkung \
        /workspace/isaaclab/isaaclab.sh -p \
        legged_lab/scripts/gmr_data_conversion.py \
        --input_pkl "/workspace/results/gmr/${rel}" \
        --output_txt "legged_lab/envs/tienkung/datasets/motion_visualization/${base}.txt"

    # Point walk.txt / run.txt at this clip — play_amp_animation.py reads the task
    # config which hardcodes amp_motion_files_display → {task}.txt (not the clip file).
    docker exec tienkung ln -sf \
        "/workspace/TienKung-Lab/legged_lab/envs/tienkung/datasets/motion_visualization/${base}.txt" \
        "/workspace/TienKung-Lab/legged_lab/envs/tienkung/datasets/motion_visualization/${TASK}.txt"

    # Step B — AMP expert data (task selects env config + obs space)
    docker exec -w /workspace/TienKung-Lab tienkung \
        /workspace/isaaclab/isaaclab.sh -p \
        legged_lab/scripts/play_amp_animation.py \
        --task=${TASK} --num_envs=1 --headless \
        --save_path "legged_lab/envs/tienkung/datasets/motion_amp_expert/${base}.txt" \
        --fps 30.0

    echo "Done [${TASK}]: ${base}"
done
```

Verify the populated folders:
```bash
ls ~/results/datasets/motion_visualization/ | wc -l   # should match number of listed clips
ls ~/results/datasets/motion_amp_expert/    | wc -l   # should match number of listed clips
```

No config change is needed — `motion_loader.py` picks up all files in the folder
automatically. Training will sample uniformly across all clips.

> **Tip:** You rarely need every clip. A few dozen varied motions (different speeds,
> directions, subjects) give AMP enough diversity. Start with a representative subset
> and add more only if the policy fails to generalise.
