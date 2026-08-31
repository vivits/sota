#!/bin/bash
# Bootstrap all three SOTA baselines (DeepEye-SQL, DAIL-SQL, CHESS) on this
# machine: clones/updates each repo's `sota` branch and builds all four
# Python environments (deepeye conda, DAIL-SQL conda, chess conda,
# sglang-venv) per README.md's "Environment setup" section.
#
# Safe to re-run: every step checks for existing state first and skips it,
# so this won't touch a repo with local changes or rebuild an env that's
# already there (important -- a CHESS run may be actively using its conda
# env and repo checkout when this runs).
#
# Explicitly OUT of scope (left as manual steps, see the printed checklist
# at the end): discovery_full.csv, BIRD dev benchmark data, and DAIL-SQL's
# 31GB dataset/ (BIRD train split for few-shot retrieval + dev DBs + prompt
# caches) -- these are data, not environment, and README.md's per-repo
# sections document exactly how to obtain them.
#
# Usage: bash setup.sh

set -uo pipefail

SOTA_DIR="/export/scratch/tsang065/sota"
CONDA_ENVS_DIR="/home/tsang065/.conda/envs"
SGLANG_VENV="/export/scratch/tsang065/sglang-venv"

cd "$SOTA_DIR" || { echo "ERROR: $SOTA_DIR not found"; exit 1; }

log() { echo "[$(date '+%F %T')] $*"; }

conda_env_exists() {
    conda env list 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

# --- 1. Clone or update each repo's `sota` branch ---------------------------

clone_or_update_repo() {
    local name="$1" fork_url="$2"
    if [[ -d "$name/.git" ]]; then
        log "$name: already cloned, fetching origin/sota..."
        if ! git -C "$name" fetch origin sota --quiet; then
            log "$name: fetch failed (offline? check manually) -- continuing with existing checkout."
            return
        fi
        # --ff-only is non-destructive: it no-ops (with a warning) instead of
        # clobbering anything if local commits or uncommitted changes exist,
        # which matters if a run is using this checkout right now.
        if git -C "$name" merge --ff-only origin/sota --quiet 2>/dev/null; then
            log "$name: fast-forwarded to latest origin/sota."
        else
            log "$name: local checkout has diverged/uncommitted changes -- left as-is, not auto-merging."
        fi
    else
        log "$name: cloning origin/sota..."
        git clone --branch sota "$fork_url" "$name"
    fi
}

log "=== Step 1/5: DeepEye-SQL repo ==="
clone_or_update_repo "DeepEye-SQL" "https://github.com/vivits/DeepEye-SQL.git"

log "=== Step 2/5: DAIL-SQL repo ==="
clone_or_update_repo "DAIL-SQL" "https://github.com/vivits/DAIL-SQL.git"

log "=== Step 3/5: CHESS repo ==="
clone_or_update_repo "CHESS" "https://github.com/vivits/CHESS.git"

# --- 2. deepeye conda env (DeepEye-SQL) --------------------------------------

log "=== Step 4/5: Python environments ==="

if conda_env_exists "deepeye"; then
    log "deepeye conda env already exists, skipping."
else
    log "Creating deepeye conda env (python 3.11)..."
    conda create -y -n deepeye python=3.11
    conda run -n deepeye pip install -r DeepEye-SQL/environment/deepeye-conda-freeze.txt
fi

if [[ ! -f DeepEye-SQL/config/config.toml ]]; then
    log "DeepEye-SQL/config/config.toml missing -- copying from tracked example."
    cp DeepEye-SQL/config/config-discovery-qwen-example.toml DeepEye-SQL/config/config.toml
fi

# --- 3. DAIL-SQL conda env ---------------------------------------------------

if conda_env_exists "DAIL-SQL"; then
    log "DAIL-SQL conda env already exists, skipping install (still re-running nltk_downloader.py, harmless if already fetched)."
else
    log "Creating DAIL-SQL conda env (python 3.8)..."
    conda create -y -n DAIL-SQL python=3.8
    conda run -n DAIL-SQL python -m pip install --upgrade pip
    conda run -n DAIL-SQL pip install -r DAIL-SQL/requirements.txt
fi
(cd DAIL-SQL && conda run -n DAIL-SQL python nltk_downloader.py)

# --- 4. chess conda env ------------------------------------------------------

if conda_env_exists "chess"; then
    log "chess conda env already exists, skipping."
else
    log "Creating chess conda env (python 3.11)..."
    conda create -y -n chess python=3.11
    conda run -n chess pip install -r CHESS/requirements.txt
fi

if [[ ! -f CHESS/.env ]]; then
    log "CHESS/.env missing -- copying from tracked .env.example."
    cp CHESS/.env.example CHESS/.env
fi

# --- 5. sglang-venv -----------------------------------------------------------

if [[ -d "$SGLANG_VENV" ]]; then
    log "sglang-venv already exists at $SGLANG_VENV, skipping."
else
    log "Building sglang-venv from deepeye's python3.11 interpreter..."
    "$CONDA_ENVS_DIR/deepeye/bin/python3" -m venv "$SGLANG_VENV"
    "$SGLANG_VENV/bin/pip" install -r environment/sglang-venv-freeze.txt
fi

# --- Done: data checklist ----------------------------------------------------

log "=== Step 5/5: data dependency checklist (not automated by this script) ==="
missing=0
check() {
    if [[ -e "$1" ]]; then
        echo "  [OK]      $1"
    else
        echo "  [MISSING] $1  -- $2"
        missing=1
    fi
}
check "discovery_full.csv" "table-discovery output from mcp-structured-query-pipeline; see README.md intro."
check "data/bird-benchmark/dev_20240627/dev.json" "BIRD dev benchmark data; see README.md intro."
check "data/bird-benchmark/dev_20240627/databases" "BIRD dev sqlite databases; see README.md intro."
check "DAIL-SQL/dataset/bird/database" "DAIL-SQL's own copy of the BIRD dev databases; see DAIL-SQL/README.md 'Data Preparation'."
check "DAIL-SQL/dataset/bird/train" "BIRD train split, used for DAIL-SQL's few-shot example retrieval (~31GB); see DAIL-SQL/README.md 'Data Preparation'."
check "DAIL-SQL/dataset/bird/enc" "Prebuilt schema-linking encoding caches; see DAIL-SQL §2 in README.md."

echo
if [[ "$missing" -eq 1 ]]; then
    log "Environments are ready, but some data dependencies above are missing -- see README.md for exact fetch steps before running generation/eval."
else
    log "All repos, environments, and data dependencies are in place. Ready for generation/eval -- see README.md's per-repo sections for the actual run commands."
fi
