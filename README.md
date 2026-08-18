# SOTA baselines: DeepEye-SQL, DAIL-SQL, CHESS

Three text-to-SQL baselines, each adapted to run against local Qwen (via sglang) using
`discovery_full.csv` (from `mcp-structured-query-pipeline`'s table-discovery step) to narrow
schema/table selection instead of ground-truth full-schema access.

All three first lived under `mcp-structured-query-pipeline/sota/` (moved 2026-08-12), then were
**decoupled into this standalone `/export/scratch/tsang065/sota/` directory** (moved 2026-08-16,
one level up, no longer nested inside `mcp-structured-query-pipeline` at all) so this doesn't
depend on push access to that repo. The only two things these baselines actually needed from
`mcp-structured-query-pipeline` — `discovery_full.csv` and the BIRD dev benchmark data — were
copied in alongside them at `sota/discovery_full.csv` and `sota/data/bird-benchmark/dev_20240627/`,
so there's no remaining dependency on `mcp-structured-query-pipeline`'s location at all. Paths
below are corrected for this layout — each repo is one level below `sota/`, so `discovery_full.csv`
and the BIRD data are reached via `../` from each repo's root.

Repo locations:
- `/export/scratch/tsang065/sota/DeepEye-SQL`
- `/export/scratch/tsang065/sota/DAIL-SQL`
- `/export/scratch/tsang065/sota/CHESS`

(`/export/scratch/tsang065/DeepEye-SQL` is also still reachable as a symlink to the path above —
a compatibility shim for the session that did the original move; safe to remove, or ignore.)

Each repo's local commits (all adaptation work: discovery-CSV integration, sglang/Qwen wiring,
logging, path fixes) are pushed to a fork under the `sota` branch, since `master`/`main` on each
fork mirrors upstream (which has since diverged):
- DeepEye-SQL: https://github.com/vivits/DeepEye-SQL/tree/sota (upstream: [HKUSTDial/DeepEye-SQL](https://github.com/HKUSTDial/DeepEye-SQL))
- DAIL-SQL: https://github.com/vivits/DAIL-SQL/tree/sota (upstream: [BeachWang/DAIL-SQL](https://github.com/BeachWang/DAIL-SQL))
- CHESS: https://github.com/vivits/CHESS/tree/sota (upstream: [ShayanTalaei/CHESS](https://github.com/ShayanTalaei/CHESS))

---

## Environment setup

Four separate Python environments are involved — two of these (`deepeye` conda, `sglang-venv`)
aren't documented anywhere upstream at all. **All four build procedures were verified 2026-08-14
by installing each fresh into a throwaway env/venv from scratch** (not just inspecting an
already-working one) — this caught and fixed two real bugs: a `PyYAML` version pin conflict in
the `deepeye` freeze file (§1) and an incorrect `sglang` version claim for `sglang-venv` (§4). The
actual built environments live entirely outside these repos (conda envs under
`/home/tsang065/.conda/envs/`, `sglang-venv` as a sibling of `sota/`) — only the small
`pip freeze` manifest files below are tracked in-repo.

### 1. `deepeye` conda env (for DeepEye-SQL) — undocumented upstream, this is the actual working path

DeepEye-SQL's own `README.md` documents a `uv sync`-based `.venv` (requires Python `>=3.12`), but
that `.venv` has known corruption (missing files for `pydantic`/`pandas`/`pytz` despite `uv.lock`
listing them correctly — a pre-existing issue, not caused by anything in this doc; `uv sync
--reinstall` fixes it if you want that path instead). **What's actually been used successfully
all session is a separate conda env, `deepeye`, on Python 3.11** — not derived from `pyproject.toml`
at all (a plain conda env with packages installed ad hoc, including `openai`, `sglang`, and several
packages `pyproject.toml` doesn't even list). To reproduce it exactly:
```bash
conda create -n deepeye python=3.11
conda activate deepeye
pip install -r /export/scratch/tsang065/sota/DeepEye-SQL/environment/deepeye-conda-freeze.txt
```
That freeze file is a `pip freeze` snapshot of the current known-good `deepeye` env (291 packages).
Run commands from inside `DeepEye-SQL/` with this env active — `app`/`runner` resolve via cwd
(`sys.path`), no install step needed for the DeepEye-SQL package itself.

**Bug found and fixed (2026-08-14)**: the freeze file originally pinned `PyYAML==6.0.1`, which
conflicts with several other pinned packages (`accelerate`, `chromadb`, `datasets`, `huggingface_hub`,
`kubernetes`, etc. all want a newer one) — `pip install -r` failed outright with
`ResolutionImpossible` on a from-scratch install, even though the already-running `deepeye` env
(installed incrementally over time via separate `pip install` calls, never all at once) was
unaffected. Fixed by re-pinning to `PyYAML==6.0.3` (what pip resolves to when left unconstrained);
verified with a clean `pip install -r` from scratch.

**Known risk, not fixed (flagging only)**: this freeze file (and the live `deepeye` env) pins
`pandas==3.0.4`, which PyPI has **yanked** — `pip install` prints `Reason for being yanked:
Reported segfaults with datetime-related functionality`. The install still succeeds (yanked just
means "don't resolve to this by default," not "blocked"), and nothing in this project's actual use
of pandas has crashed. But this is a real known-bad release sitting in the environment currently
running the paused CHESS job and every other real result in this repo — consider pinning to a
different pandas version if you hit any unexplained crash, especially around datetime columns.

### 2. `DAIL-SQL` conda env — already documented upstream, matches what's installed

`DAIL-SQL/README.md`'s "Environment Setup" section is accurate and already used successfully:
```bash
conda create -n DAIL-SQL python=3.8
conda activate DAIL-SQL
python -m pip install --upgrade pip
pip install -r requirements.txt   # from inside DAIL-SQL/ — already includes openai>=1.0 for sglang
python nltk_downloader.py
```
CoreNLP (needed only to regenerate the `dataset/bird/enc/*.jsonl` schema-linking caches, not for a
normal discovery-CSV run since those caches already exist) and the GloVe vector cache are separate,
already-fetched data dependencies — see `DAIL-SQL/README.md`'s "Environment Setup"/"Data Preparation"
sections if you need to rebuild those from scratch.

### 3. `chess` conda env — mostly documented upstream, missing the Python version

`CHESS/README.md`'s "Setting up the Environment" section says `pip install -r requirements.txt` but
never specifies a Python version. The actual working env uses **Python 3.11**:
```bash
conda create -n chess python=3.11
conda activate chess
pip install -r requirements.txt   # from inside CHESS/
```
Two things the stock README's `.env` template doesn't reflect: (a) `db_catalog/preprocess.py` and
`retrieve_entity.py` were patched to use a local HuggingFace BGE embedding model
(`BAAI/bge-base-en-v1.5`, CPU) instead of `OpenAIEmbeddings`, so no real `OPENAI_API_KEY`/GCP
credentials are actually needed (a placeholder string in `.env` is enough to satisfy
`langchain_openai`'s import-time validation); (b) the real `.env` in use has
`DB_ROOT_PATH="./data/dev"`, `DATA_MODE="dev"`, `DB_ROOT_DIRECTORY="./data/dev/dev_databases"` — see
`CHESS/.env` directly (gitignored, not shown in the README).

### 4. `sglang-venv` — undocumented anywhere, built from scratch this session

Not a conda env — a plain `venv`, built from the `deepeye` conda env's own Python 3.11 interpreter
(any Python 3.11 works equally well; that's just what was used):
```bash
/home/tsang065/.conda/envs/deepeye/bin/python3 -m venv /export/scratch/tsang065/sglang-venv
/export/scratch/tsang065/sglang-venv/bin/pip install -r /export/scratch/tsang065/sota/environment/sglang-venv-freeze.txt
```
That freeze file is a `pip freeze` snapshot of the current known-good venv (227 packages, `sglang==0.5.13.post1` —
verified live by installing it fresh into a throwaway venv from the documented `deepeye`-Python-3.11 interpreter).

Three non-obvious runtime requirements discovered the hard way this session (all three needed
together — missing any one breaks the server on this machine's GPUs, RTX PRO 6000 Blackwell):
- **`--attention-backend triton`** — sglang auto-selects `flashinfer` by default, whose CUDA-graph
  capture falsely reports `sm75` incompatibility on this GPU.
- **`sglang-venv/bin` and `/export/scratch/tsang065/cuda-12.9/bin` must be on `PATH` *ahead of* the
  system default** — the triton backend JIT-compiles a kernel via `ninja` (only found if
  `sglang-venv/bin` is on `PATH`) using `nvcc` (the system default at `/usr/bin/nvcc` is CUDA 12.0,
  which doesn't support this GPU's `sm_120`; CUDA 12.9 at `/export/scratch/tsang065/cuda-12.9` does).
- `HF_HOME=/export/scratch/tsang065/hf_cache` — so the model downloads/caches to scratch, not `$HOME`.

All of this is already baked into the server-launch commands in each section below — this note is
just so the *why* isn't a mystery if you ever need to rebuild `sglang-venv` from scratch or debug a
launch failure.

---

## DeepEye-SQL

**1. Start the sglang server:**
```bash
export HF_HOME=/export/scratch/tsang065/hf_cache
export CUDA_HOME=/export/scratch/tsang065/cuda-12.9
export PATH=/export/scratch/tsang065/cuda-12.9/bin:/export/scratch/tsang065/sglang-venv/bin:$PATH
/export/scratch/tsang065/sglang-venv/bin/python3 -m sglang.launch_server \
  --model-path /export/scratch/tsang065/hf_cache/models--Qwen--Qwen3.6-27B-FP8/snapshots/e89b16ebf1988b3d6befa7de50abc2d76f26eb09 \
  --port 30000 --mem-fraction-static 0.8 --max-running-requests 8 \
  --attention-backend triton
```

**2. In another terminal, activate the `deepeye` conda env and seed schema-linking:**
```bash
conda activate deepeye
cd /export/scratch/tsang065/sota/DeepEye-SQL

python runner/inject_discovery_schema_linking.py \
  --discovery_csv ../discovery_full.csv \
  --bird_data_dir ../data/bird-benchmark/dev_20240627 \
  --config config/config.toml
```

**3. Run generation (logging is automatic):**
```bash
python runner/run_sql_generation.py 2>&1 | tee logs/full_run_sql_generation_$(date +%Y%m%d_%H%M%S).log
```

**4. Evaluate** — does not need the sglang server (pure SQL execution/comparison against the BIRD sqlite DBs):
```bash
python runner/evaluation.py 2>&1 | tee logs/evaluation_$(date +%Y%m%d_%H%M%S).log
# → prints "Overall Execution Accuracy: XX.XX%"
```

**5. Optional — bundle accuracy + latency/token stats into a JSON report:**
```bash
python runner/export_eval_report.py \
  --snapshot_path workspace/sql_selection/bird/dev.snapshot \
  --ex_accuracy <accuracy_from_step_4> \
  --output results/eval_report.json
```

Note: `SQLGenerationRunner` checkpoints per item and skips already-completed questions
(`is_stage_complete`), and its dataset loader prefers the existing `sql_generation` snapshot
over re-seeding from schema-linking — so re-running step 2+3 against the real completed run
is safe (step 3 becomes a no-op, no LLM calls) rather than destructive.

---

## DAIL-SQL

**1. Start the sglang server (same as DeepEye-SQL):**
```bash
export HF_HOME=/export/scratch/tsang065/hf_cache
export CUDA_HOME=/export/scratch/tsang065/cuda-12.9
export PATH=/export/scratch/tsang065/cuda-12.9/bin:/export/scratch/tsang065/sglang-venv/bin:$PATH
/export/scratch/tsang065/sglang-venv/bin/python3 -m sglang.launch_server \
  --model-path /export/scratch/tsang065/hf_cache/models--Qwen--Qwen3.6-27B-FP8/snapshots/e89b16ebf1988b3d6befa7de50abc2d76f26eb09 \
  --port 30000 --mem-fraction-static 0.8 --max-running-requests 8 \
  --attention-backend triton
```

**2. Build prompts, narrowed to `discovery_full.csv`'s table selections:**
```bash
conda activate DAIL-SQL   # python 3.8.20, separate env from deepeye
cd /export/scratch/tsang065/sota/DAIL-SQL

python generate_question.py --data_type bird \
  --split test --tokenizer gpt-3.5-turbo --prompt_repr TEXT \
  --selector_type EUCDISQUESTIONMASK --k_shot 7 --example_type QA \
  --max_seq_len 4096 \
  --discovery_csv ../discovery_full.csv
```
`--discovery_csv` is a real, already-wired flag (`generate_question.py:64-67`) — no adapter script
needed, unlike DeepEye-SQL. Expect harmless `[discovery_schema] table 'X' not found in schema,
skipping` noise for candidates that don't resolve (falls back to full schema) — this is a data
quality artifact in `discovery_full.csv` itself (e.g. a nonexistent `generic_attribute` table for
68 `superhero`-db questions), not a bug.

**3. Generate SQL via the sglang Qwen server (logging is automatic):**
```bash
QUESTION_DIR="dataset/process/BIRD-TEST_TEXT_7-SHOT_EUCDISQUESTIONMASK_QA-EXAMPLE_CTX-200_ANS-4096"

python ask_llm.py \
  --model "Qwen/Qwen3.6-27B-FP8" \
  --base_url "http://localhost:30000/v1" \
  --question "./${QUESTION_DIR}/" \
  --db_dir ./dataset/bird/database \
  --n 1
```
**Important**: the `QUESTION_DIR="..."` line above must be its own separate statement (a real
newline before the next command) — if it ends up joined onto the same line as `python ask_llm.py`
(e.g. from a bad copy-paste), bash treats `QUESTION_DIR=value command` as a one-off environment
variable for that command's *child process only*, not a shell variable, so `${QUESTION_DIR}` in
the same command's own arguments silently expands to empty, producing `--question ./` instead of
the real path (`FileNotFoundError: .../questions.json`).

This takes ~76 minutes for the full 1534 questions. Since `ask_llm.py` writes output incrementally
and only writes `STATS_MODEL-*.json` at the very end, an interrupted run leaves a partial
`RESULTS_MODEL-*.txt` with no way to resume — if interrupted, just re-run this step from scratch.
Recommended for a real run:
```bash
nohup python ask_llm.py \
  --model "Qwen/Qwen3.6-27B-FP8" \
  --base_url "http://localhost:30000/v1" \
  --question "./${QUESTION_DIR}/" \
  --db_dir ./dataset/bird/database \
  --n 1 \
  > logs/ask_llm_run.log 2>&1 &
echo "pid: $!"
```
Writes `RESULTS_MODEL-Qwen-Qwen3.6-27B-FP8.txt` (predicted SQL) and `STATS_MODEL-Qwen-Qwen3.6-27B-FP8.json`
(per-question + aggregate latency/tokens) into `$QUESTION_DIR`.

**4. Convert to BIRD's submission format** — requires step 3 to have finished all 1534 questions
(`to_bird_output.py` asserts `len(dev) == len(queries)`, purely positional, no partial-run support):
```bash
python to_bird_output.py \
  --dail_output "./${QUESTION_DIR}/RESULTS_MODEL-Qwen-Qwen3.6-27B-FP8.txt" \
  --bird_dev ./dataset/bird/dev.json
```

**5. Evaluate execution accuracy:**
```bash
python runner_evaluate_bird.py \
  --predictions "${QUESTION_DIR}/RESULTS_MODEL-Qwen-Qwen3.6-27B-FP8.txt" \
  --dev_json dataset/bird/dev.json \
  --db_dir dataset/bird/database \
  --output "${QUESTION_DIR}/EX_MODEL-Qwen-Qwen3.6-27B-FP8.json"
```
Verified live (before the move): reproduces 53.46% EX (820/1534) — simple 58.92%, moderate 45.26%,
challenging 44.83%.

**6. Optional — combine into one report:**
```bash
python runner_export_eval_report.py \
  --stats_json "${QUESTION_DIR}/STATS_MODEL-Qwen-Qwen3.6-27B-FP8.json" \
  --ex_json "${QUESTION_DIR}/EX_MODEL-Qwen-Qwen3.6-27B-FP8.json" \
  --output results/eval_report_discovery_qwen.json
```

**Overwrite warning**: `ask_llm.py`/`to_bird_output.py` write into the same filenames every time
you run steps 3–5 with default indices (`RESULTS_MODEL-*.txt` etc. in `$QUESTION_DIR`) — a real
full run will overwrite the existing 53.46% result files (and since LLM inference isn't perfectly
deterministic run-to-run, a redo may not reproduce the exact same predictions). Use
`--mini_index_path` (a JSON list of row indices, e.g. `[0]`) for a small-scale test without
touching the real ones — it writes to `*_MINI.txt`/`*_MINI.json` instead. A backup of the current
real results exists at `/export/scratch/tsang065/sota_results_backup/2026-08-10/DAIL-SQL/`.

---

## CHESS

**1. Start the sglang server** — note CHESS's wired config points at **port 30001**, not 30000:
```bash
export HF_HOME=/export/scratch/tsang065/hf_cache
export CUDA_HOME=/export/scratch/tsang065/cuda-12.9
export PATH=/export/scratch/tsang065/cuda-12.9/bin:/export/scratch/tsang065/sglang-venv/bin:$PATH
export LD_LIBRARY_PATH=/export/scratch/tsang065/cuda-12.9/lib64:${LD_LIBRARY_PATH:-}
/export/scratch/tsang065/sglang-venv/bin/python3 -m sglang.launch_server \
  --model-path /export/scratch/tsang065/hf_cache/models--Qwen--Qwen3.6-27B-FP8/snapshots/e89b16ebf1988b3d6befa7de50abc2d76f26eb09 \
  --port 30001 --host 127.0.0.1 \
  --tool-call-parser qwen --enable-custom-logit-processor \
  --mem-fraction-static 0.8 --max-running-requests 16 --tp 1 \
  --attention-backend triton --sampling-backend pytorch --watchdog-timeout 600
```

**2. Run generation** — `--discovery_csv` is already fully wired (schema selection replaced by
discovery lookups; logging via `LLMUsageTracker`, already hooked in):
```bash
conda activate chess
cd /export/scratch/tsang065/sota/CHESS

python3 -u ./src/main_with_discovery.py \
  --data_mode dev \
  --data_path ../data/bird-benchmark/dev_20240627/dev.json \
  --config run/configs/CHESS_IR_CG_UT_discovery_qwen.yaml \
  --num_workers 6 --log_level warning \
  --discovery_csv ../discovery_full.csv
```
Writes `-predictions.json` into a fresh timestamped
`results/dev/CHESS_IR_CG_UT_discovery_qwen/dev/<TIMESTAMP>/` — never overwrites a prior run.
`-predictions.json` updates after *every* question (file-locked), so interrupting this run at
any point is safe — whatever finished is already recorded.

**`-llm_usage_stats.json` bug found and fixed (2026-08-13)**: originally this file was only written
once, at the natural end of `main_with_discovery.py` (`write_llm_usage_stats()`, called after
`run_tasks()` completes). Since the first full run needed many `watchdog.sh`-triggered restarts
(sglang silently stalling), every restart killed the process before it reached that point — so
only the *one* process invocation that happened to run to a clean completion ever got its stats
flushed. Checked on the original run (`2026-07-19T22:09:37.026384/`): **only 53 of 1534 questions
(3.5%) have logged token/latency data**; the other 1481 have none, permanently — no per-call
token data exists anywhere else on disk to recover it (per-question execution-history files record
step-level wall-clock time but no tokens). Predictions themselves are unaffected (1534/1534 intact,
and the 58.67% EX result below is still fully valid).

Fixed in `run_manager_with_discovery.py`: `task_done()` now calls
`_flush_llm_usage_stats_incremental()` after every question, mirroring `-predictions.json`'s own
file-locked read-modify-write pattern, so a killed/restarted run can no longer lose this data.
Verified live with a 2-question/2-worker smoke test (entries appeared in `-llm_usage_stats.json`
immediately after each question finished, not just at the end).

**A fresh full run using the patched code is in progress** (started 2026-08-13, to get complete
logging this time) at:
```
results/dev/CHESS_IR_CG_UT_discovery_qwen/dev/2026-08-13T23:23:59.773432/
```
**Currently paused at 64/1534** (intentionally stopped — both `-predictions.json` and
`-llm_usage_stats.json` confirmed valid and in sync at 64 entries each, no corruption). To resume:
```bash
nohup bash run/watchdog.sh > logs/watchdog.log 2>&1 &
```
(`watchdog.sh`'s `RESULT_DIR` is already pointed at this directory.) This starts a fresh sglang
server on GPU 1 — check `nvidia-smi` first, since both GPUs are sometimes fully occupied by other
users on this shared machine, and don't use a GPU/port someone else is already using.

The original `2026-07-19T22:09:37.026384/` run (1534/1534 predictions, but only 53/1534 usage-stats
entries) is left as-is — still valid for EX scoring, just incomplete for latency/token analysis.

**3. Evaluate** — CHESS ships no BIRD execution-accuracy script upstream, so one was added
(`runner_evaluate_bird.py`, adapted from DAIL-SQL's proven eval logic to parse CHESS's
`{question_id: "SQL\t----- bird -----\tdb_id"}` format). Unlike DAIL-SQL's evaluator, it tolerates
a partial/incomplete `-predictions.json` gracefully (missing entries count as `"no_prediction"`,
not a crash):
```bash
python3 runner_evaluate_bird.py \
  --predictions "results/dev/CHESS_IR_CG_UT_discovery_qwen/dev/<TIMESTAMP>/-predictions.json" \
  --dev_json ../data/bird-benchmark/dev_20240627/dev.json \
  --db_dir ../data/bird-benchmark/dev_20240627/databases \
  --output "results/dev/CHESS_IR_CG_UT_discovery_qwen/dev/<TIMESTAMP>/-ex_report.json"
```
Verified live against the completed run: 58.67% EX (900/1534) — simple 64.76%, moderate 51.29%,
challenging 43.45%. Report also saved at
`results/dev/CHESS_IR_CG_UT_discovery_qwen/dev/2026-07-19T22:09:37.026384/-ex_report.json`, and
backed up at `/export/scratch/tsang065/sota_results_backup/2026-08-10/CHESS/`.

---

## Results summary (BIRD dev, discovery-filtered schema, Qwen3.6-27B-FP8)

| System | EX | simple | moderate | challenging |
|---|---|---|---|---|
| DeepEye-SQL | 65.65% | — | — | — |
| CHESS | 58.67% | 64.76% | 51.29% | 43.45% |
| DAIL-SQL | 53.46% | 58.92% | 45.26% | 44.83% |

All three evaluators compute the identical official BIRD EX formula
(`set(pred_rows) == set(gold_rows)`, no rounding/multiset tricks) against the same BIRD sqlite DBs.
DeepEye-SQL uses a 600s SQL execution timeout vs. 30s for DAIL-SQL/CHESS — checked impact: zero
predictions timed out in either DAIL-SQL's or CHESS's run, only 2 (identical) gold queries did, so
this accounts for ≤0.13 percentage points, not the actual gaps between systems.

**Latency/token comparability caveat**: this table is EX only, deliberately — CHESS's per-query
latency/token data for the run above is only 3.5% complete (see the `-llm_usage_stats.json` bug
under CHESS §2 above); a fresh run with the fix applied is in progress (paused at 64/1534) and will
have complete data once finished. Don't compare latency/tokens across systems using the current
CHESS numbers until that fresh run completes.
