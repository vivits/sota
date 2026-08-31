# Setup

```bash
bash setup.sh
```

That's it. Running `setup.sh` clones/updates the `sota` branch of all three repos
(DeepEye-SQL, DAIL-SQL, CHESS) and builds all four Python environments (`deepeye`,
`DAIL-SQL`, `chess` conda envs + `sglang-venv`) — skipping anything already present,
so it's safe to re-run anytime, including while a run is in progress.

It does **not** fetch data (see below) — at the end it prints a checklist of what's
missing so you know what to go get. See `README.md` for the actual generation/eval
commands once setup is done.

## Data setup.sh does NOT fetch

Data isn't tracked in git (too large / not this repo's to redistribute), so it has
to be placed manually:

| Path | What | Used by |
|---|---|---|
| `discovery_full.csv` | Table-discovery output from `mcp-structured-query-pipeline` | all three |
| `data/bird-benchmark/dev_20240627/dev.json` | BIRD dev question set | DeepEye-SQL, CHESS |
| `data/bird-benchmark/dev_20240627/databases/` | BIRD dev sqlite DBs | DeepEye-SQL, CHESS |
| `DAIL-SQL/dataset/bird/database/` | DAIL-SQL's own copy of the BIRD dev DBs | DAIL-SQL |
| `DAIL-SQL/dataset/bird/train/` | BIRD train split (~31GB, few-shot example retrieval) | DAIL-SQL |
| `DAIL-SQL/dataset/bird/enc/` | Prebuilt schema-linking encoding caches | DAIL-SQL |

All paths are relative to this directory (`sota/`). `setup.sh`'s last step checks
each of these and prints `[OK]`/`[MISSING]` for every one. For DAIL-SQL's data,
see `DAIL-SQL/README.md`'s "Data Preparation" section if you need to rebuild it
from scratch (BIRD download, GloVe vectors, CoreNLP).

## Config files setup.sh materializes automatically

Two config files aren't tracked in git either (gitignored on purpose — they hold
per-machine paths), but `setup.sh` copies a tracked example into place if missing,
so no manual step is needed unless you want to customize them:

- `DeepEye-SQL/config/config.toml` ← `DeepEye-SQL/config/config-discovery-qwen-example.toml`
- `CHESS/.env` ← `CHESS/.env.example`
