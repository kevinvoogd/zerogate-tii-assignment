#!/usr/bin/env bash
# prune_amass_cmu.sh — Extract CMU and HumanEva AMASS archives, delete unlisted
# clips, and recompress each to a _reduced.tar.bz2.
#
# Usage:
#   ./scripts/prune_amass_cmu.sh <amass_dir> [manifest]
#
#   amass_dir   directory containing CMU.bz2 and/or HumanEva.tar.bz2
#   manifest    path to motion_tasks.csv (default: alongside this script)
#
# Outputs written to <amass_dir>/:
#   CMU/                      pruned clips
#   HumanEva/                 pruned clips
#   CMU_reduced.tar.bz2       recompressed pruned CMU
#   HumanEva_reduced.tar.bz2  recompressed pruned HumanEva
#
# Rsync to Brev after this script completes:
#   rsync -avz --progress <amass_dir>/CMU/      ubuntu@<brev-ip>:~/data/amass/CMU/
#   rsync -avz --progress <amass_dir>/HumanEva/ ubuntu@<brev-ip>:~/data/amass/HumanEva/

set -euo pipefail

AMASS_DIR="${1:?Usage: $0 <amass_dir> [path/to/motion_tasks.csv]}"
AMASS_DIR="${AMASS_DIR%/}"   # strip trailing slash
MANIFEST="${2:-$(dirname "$0")/motion_tasks.csv}"

if [[ ! -d "$AMASS_DIR" ]]; then
    echo "Error: directory not found: $AMASS_DIR" >&2; exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest not found: $MANIFEST" >&2; exit 1
fi

# ── Build lookup table ────────────────────────────────────────────────────────
# CMU key:      subject_trial    e.g. "09_01"       (trial = 2nd _-field of fname)
# HumanEva key: subject_fname    e.g. "S1_Walking_3" (full filename stem)
declare -A LISTED
while IFS=, read -r subj trial task; do
    [[ "$subj" == "subject" ]] && continue
    LISTED["${subj}_${trial}"]=1
done < "$MANIFEST"
echo "Manifest loaded: ${#LISTED[@]} listed clips."

# ── Helper: build lookup key from an .npz path ───────────────────────────────
get_key() {
    local npz="$1"
    local subj fname trial
    subj=$(basename "$(dirname "$npz")")
    fname=$(basename "$npz" _stageii.npz)
    if [[ "$subj" =~ ^[0-9]+$ ]]; then
        # CMU: numeric subject folder; trial is 2nd _-delimited field of filename
        trial=$(echo "$fname" | cut -d_ -f2)
    else
        # HumanEva: alphabetic subject (S1/S2/S3); use full motion name as trial
        trial="$fname"
    fi
    echo "${subj}_${trial}"
}

# ── Helper: prune a dataset directory ────────────────────────────────────────
prune_dir() {
    local outdir="$1" label="$2"
    local kept=0 deleted=0
    echo "Pruning $label ..."
    while IFS= read -r -d '' npz; do
        local key
        key=$(get_key "$npz")
        if [[ -n "${LISTED[$key]+_}" ]]; then
            kept=$((kept + 1))
        else
            rm "$npz"
            deleted=$((deleted + 1))
        fi
    done < <(find "$outdir" -name '*_stageii.npz' -print0)
    find "$outdir" -mindepth 1 -maxdepth 1 -type d -empty -delete
    echo "  Kept: $kept  |  Deleted: $deleted  |  Empty dirs removed."
}

# ── Helper: extract archive if folder not already present ────────────────────
extract_if_needed() {
    local archive="$1" outdir="$2"
    if [[ -f "$archive" ]]; then
        echo "Extracting $(basename "$archive") → $AMASS_DIR/ ..."
        tar -xjf "$archive" -C "$AMASS_DIR"
        echo "  Extracted: $outdir"
    elif [[ -d "$outdir" ]]; then
        echo "$(basename "$outdir")/ already present — skipping extraction."
    else
        echo "Warning: neither $archive nor $outdir found — skipping." >&2
        return 1
    fi
}

# ── Helper: recompress pruned folder to _reduced.tar.bz2 ─────────────────────
recompress() {
    local outdir="$1"
    local name reduced size
    name=$(basename "$outdir")
    reduced="${AMASS_DIR}/${name}_reduced.tar.bz2"
    echo "Compressing $name → $(basename "$reduced") ..."
    tar -cjf "$reduced" -C "$AMASS_DIR" "$name"
    size=$(du -sh "$reduced" | cut -f1)
    echo "  Written: $reduced  ($size)"
}

# ── CMU ───────────────────────────────────────────────────────────────────────
CMU_DIR="$AMASS_DIR/CMU"
extract_if_needed "$AMASS_DIR/CMU.bz2" "$CMU_DIR"
prune_dir "$CMU_DIR" "CMU"
recompress "$CMU_DIR"
echo ""

# ── HumanEva ──────────────────────────────────────────────────────────────────
HUMANEVA_DIR="$AMASS_DIR/HumanEva"
extract_if_needed "$AMASS_DIR/HumanEva.tar.bz2" "$HUMANEVA_DIR"
prune_dir "$HUMANEVA_DIR" "HumanEva"
recompress "$HUMANEVA_DIR"
echo ""

echo "════════════════════════════════════"
echo "Done. Rsync to Brev:"
echo "  rsync -avz --progress $CMU_DIR/      ubuntu@<brev-ip>:~/data/amass/CMU/"
echo "  rsync -avz --progress $HUMANEVA_DIR/ ubuntu@<brev-ip>:~/data/amass/HumanEva/"
