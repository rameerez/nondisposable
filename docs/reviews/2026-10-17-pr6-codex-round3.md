Scoped to `84eb12c..5fd7369`. No files modified. All original round-2 reproductions pass with the current schema:

| Item | Result | Concrete reproduction |
|---|---|---|
| R1-2 | VERIFIED | Sole primary lists employer; rollback removes it and restores bundled `mailinator.com`. |
| R1-5 | VERIFIED | 6,000 `xN.anonaddy.com` entries + employer: rejected with count **1**; seed retained. |
| R1-6 | VERIFIED | `100→60→59→58→57→56`, pruning each time; **30 rejected**, baseline remains 100. |
| R1-8 | VERIFIED | `a→root`, `mid→root`, `b→mid`; `mid` fetch fails. Employer shared by `a/b` stays unblocked. |
| R1-10 | VERIFIED | Direct normalization of 4,000 distinct Unicode codepoints: **0.00033 s**. |
| R1-12 | VERIFIED | `user@ｔｅｍｐｍａｉｌ.com` matches ASCII row. |
| E1 | VERIFIED | Four/twenty levels: table, additions, exclusions, PSL boundary and single-query checks pass. |
| #13 | VERIFIED | Inject newer S2 immediately before rollback acquires lock: **S2 withdrawn**. |
| #14 | VERIFIED | Fetch starts 09:00; poison accepted 09:01, clean 09:02; delayed clean finishes 09:03. Clean remains newest. |
| #15 | VERIFIED | 4,000 parent labels and 8 KB label return promptly, below 0.5 s. |
| #16 | VERIFIED | Fourteen correlated mirrors × 1,000 domains: ~0.01 s. All 31 voter sets × five thresholds match exhaustive results. |

R1-4/R1-7 remain **DISCLOSED**. [README warnings](/Users/javi/GitHub/nondisposable-b/README.md:355) and [CHANGELOG](/Users/javi/GitHub/nondisposable-b/CHANGELOG.md:12) accurately describe the races and give actionable single-runner/idle-rollback and quiesced-rollout instructions.

Legacy Unicode exact/parent matching, exclusions and disabled parent matching passed. The migration template creates `high_water_count` correctly for hosts without a snapshots table.

Four **new major defects** were reproduced:

1. **Existing snapshot tables cannot refresh.** A table created by the previous PR migration lacks `high_water_count`; refresh now raises `NoMethodError` at [domain_list_updater.rb:238](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:238). The changed [template](/Users/javi/GitHub/nondisposable-b/lib/generators/nondisposable/templates/create_nondisposable_source_snapshots.rb.erb:12) only creates tables; rerunning it fails with “table already exists.” No additive column migration exists.

2. **Pre-NFKC length check creates a Unicode bypass.** Store the canonical domain for `("é" * 32) + ".com"`. The equivalent decomposed input `("e\u0301" * 32) + ".com"` passes because its raw label exceeds 63 characters and [skips normalization](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain.rb:108). `84eb12c` blocked it; HEAD allows it.

3. **The 1,024 guard bypasses canonical matching.** `("\u00ad" * 1013) + "tempmail.com"` has 1,025 characters. `Domain.normalize` returns `tempmail.com`, but the [early return](/Users/javi/GitHub/nondisposable-b/app/models/nondisposable/disposable_domain.rb:27) allows it despite that row being blocked. `84eb12c` blocked it.

4. **Policy changes make baselines incomparable; reset cannot recover.** Accept 100 relay subdomains + 20 ordinary domains with `block_privacy_relays=true`; switch it to false. The unchanged payload is rejected as **20 versus 120**. `reset_baseline` copies the stale count **120**, so rejection continues. [Counting](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:230) and [reset](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:124) need comparable policy baselines. The same sequence succeeded at `84eb12c`.

not ready: normalization bypasses and snapshot schema/baseline regressions.