# Results by BIRD database (DeepEye-SQL, DAIL-SQL)

Full BIRD dev set, 1,534 questions, discovery-filtered schema, Qwen3.6-27B-FP8 (local sglang).
Execution accuracy (EX) checks whether the predicted row set equals the gold row set, run against
the live sqlite database (600s timeout for DeepEye-SQL, 30s for DAIL-SQL -- see sota/README.md;
checked impact of this difference: <=0.13 percentage points, not a driver of the gaps below).
Per-item correctness for DeepEye-SQL was not persisted by its own pipeline and was recomputed here
via the same set(pred_rows) == set(gold_rows) comparison as runner/evaluation.py
(DeepEye-SQL/runner/analyze_by_db.py); DAIL-SQL's numbers reuse its own already-computed
by_db breakdown (runner_evaluate_bird.py) joined with STATS_MODEL's per-question latency/tokens.

### DeepEye-SQL

| Database | N | Correct | EX | Avg latency (s) | Avg input tok | Avg output tok |
|---|---:|---:|---:|---:|---:|---:|
| superhero | 129 | 113 | 87.6% | 1104.5 | 11,021 | 25,185 |
| student_club | 158 | 114 | 72.2% | 876.1 | 16,115 | 47,569 |
| european_football_2 | 129 | 93 | 72.1% | 1145.1 | 48,977 | 34,727 |
| california_schools | 89 | 60 | 67.4% | 2446.7 | 58,432 | 42,764 |
| card_games | 191 | 123 | 64.4% | 1009.9 | 42,149 | 19,459 |
| codebase_community | 186 | 119 | 64.0% | 952.4 | 18,172 | 30,620 |
| formula_1 | 174 | 111 | 63.8% | 969.9 | 20,283 | 28,986 |
| toxicology | 145 | 92 | 63.5% | 2097.7 | 9,903 | 33,907 |
| thrombosis_prediction | 163 | 91 | 55.8% | 880.4 | 31,182 | 36,518 |
| financial | 106 | 57 | 53.8% | 5734.8 | 25,514 | 90,253 |
| debit_card_specializing | 64 | 34 | 53.1% | 1096.6 | 14,020 | 63,622 |
| **Overall** | **1534** | **1007** | **65.65%** | **1506.5** | **26,445** | **37,819** |

### DAIL-SQL

| Database | N | Correct | EX | Avg latency (s) | Avg input tok | Avg output tok |
|---|---:|---:|---:|---:|---:|---:|
| superhero | 129 | 89 | 69.0% | 1.3 | 798 | 50 |
| european_football_2 | 129 | 87 | 67.4% | 2.6 | 1,302 | 100 |
| student_club | 158 | 97 | 61.4% | 2.8 | 858 | 112 |
| codebase_community | 186 | 113 | 60.8% | 1.6 | 839 | 62 |
| card_games | 191 | 107 | 56.0% | 1.5 | 1,061 | 57 |
| thrombosis_prediction | 163 | 88 | 54.0% | 1.9 | 1,185 | 73 |
| formula_1 | 174 | 88 | 50.6% | 4.5 | 880 | 180 |
| toxicology | 145 | 65 | 44.8% | 3.6 | 832 | 144 |
| debit_card_specializing | 64 | 27 | 42.2% | 5.2 | 999 | 206 |
| california_schools | 89 | 33 | 37.1% | 2.7 | 1,092 | 107 |
| financial | 106 | 26 | 24.5% | 8.2 | 885 | 331 |
| **Overall** | **1534** | **820** | **53.46%** | **3.0** | **969** | **118** |

