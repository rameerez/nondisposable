**A. Round-1 fixes**

1. **R1-1 — verified.** [public_suffix.rb:66](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/public_suffix.rb:66): Parent matching stops at the registrable boundary. Tests cover `*.sch.uk`, `!city.kawasaki.jp`, and public-suffix rows.

2. **R1-2 [blocker] — incomplete.** [domain_list_updater.rb:330](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:330): Roll back a sole primary’s first snapshot: the merged list becomes empty, publication refuses it, and `seed!` refuses the populated table. Reproduced: `rollback` returns false; the employer remains blocked. The test requires another primary. **Fix:** explicitly replace the withdrawn list with a safe bundled fallback, including when the table is populated.

3. **R1-3 — verified.** [source_snapshot.rb:58](/Users/javi/GitHub/nondisposable-b/app/models/nondisposable/source_snapshot.rb:58): Rolled-back hashes survive pruning. The regression exceeds retention and confirms identical poison remains rejected.

4. **R1-4 [major] — incomplete.** [domain_list_updater.rb:383](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:383): SQLite has only a process lock. Process A reads poisoned snapshots; B rolls back and publishes clean data; A resumes and republishes its stale merge. Moving the domain-table read inside its transaction does not protect earlier snapshot reads. **Fix:** serialize the entire snapshot decision/publication operation across processes, using an immediate SQLite transaction before those reads. Existing tests only count advisory-lock calls.

5. **R1-5 [major] — incomplete.** [domain_list_updater.rb:203](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:203): Reproduced under defaults: 6,000 distinct `xN.anonaddy.com` entries plus `victim-employer.com` pass acceptance with count 6,001; filtering removes the relay entries and replaces the seed with the employer alone. **Fix:** count upstream entries surviving publication filtering, using comparable baselines and excluding host additions. Tests cover suffix padding, not relay padding.

6. **R1-6 [major] — incomplete.** [source_snapshot.rb:54](/Users/javi/GitHub/nondisposable-b/app/models/nondisposable/source_snapshot.rb:54): Failure retention is tested, but accepted snapshots still erase the baseline. Reproduced with pruning after each acceptance: `100 → 60 → 59 → 58 → 57 → 56 → 30`, all accepted. **Fix:** persist the high-water baseline independently of retained payloads; test accepted cuts beyond retention.

7. **R1-7 [major] — partial, disclosed.** [domain_list_updater.rb:351](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:351): The SQLite domain-table read moved inside the transaction. Legacy writers remain unsafe: after a new PostgreSQL publisher reads its diff, an old writer inserts a withdrawn employer; the new publisher never schedules that unseen row for deletion and can finish last while retaining it. **Fix:** quiesce legacy updater jobs during rollout, or use database table locking and full replacement. No interleaving regression exists.

8. **R1-8 [major] — incomplete.** [source_merge.rb:41](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/source_merge.rb:41): Ancestry uses only sources having snapshots. Configure `a→root`, `mid→root`, `b→mid`; let `mid` fail its first fetch. Reproduced: `a` and `b` falsely corroborate an employer; adding a clean snapshot for `mid` removes the block. **Fix:** build ancestry from every configured source, independently of snapshot availability. Existing tests cover direct shared ancestors.

9. **R1-9 — verified.** [precedence.rb:75](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/precedence.rb:75): Excluding `anonaddy.com` no longer disables its relay allowance. The regression checks validation/filter parity.

10. **R1-10 — verified for the encoder.** [domain.rb:71](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain.rb:71): Oversized Unicode labels bypass punycode encoding; the 4,000-codepoint reproduction completes promptly. No committed regression test covers this limit. Parent-walk exhaustion remains below.

11. **R1-11 — verified.** [source_fetcher.rb:31](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/source_fetcher.rb:31): The absolute timeout encloses connection establishment, headers, and body. The stalled-exchange test exercises expiration before body processing.

12. **R1-12 — verified.** [domain.rb:88](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain.rb:88): NFKC maps `ｔｅｍｐｍａｉｌ.com` to `tempmail.com`. Manually reproduced; no committed fullwidth regression test.

**E1 — verified for valid DNS names.** [disposable_domain.rb:38](/Users/javi/GitHub/nondisposable-b/app/models/nondisposable/disposable_domain.rb:38): Tests cover four and twenty levels, additions, exclusions, suffix boundaries, and one database query. The assumed input-length bound is unenforced.

**New findings**

13. **[major] Rollback selects its target before acquiring the lock.** [domain_list_updater.rb:95](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:95): Rollback reads snapshot S1; a concurrent refresh accepts newer S2 containing the same employer; rollback acquires the lock, withdraws S1, and successfully publishes S2. Reproduced by deterministic interleaving. **Fix:** select and validate the rollback target inside the lock; add an interleaving regression.

14. **[major] An unchanged delayed fetch can restore an older poisoned snapshot.** [domain_list_updater.rb:188](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/domain_list_updater.rb:188): `fetched_at` is captured before downloading. A job started at 09:00 finishes after poison at 09:01 was replaced by clean data at 09:02. Its identical clean response moves the clean snapshot back to 09:00; `last_good` now selects the 09:01 poison. Reproduced: the employer becomes blocked again. **Fix:** prevent unchanged refreshes from decreasing snapshot ordering timestamps; test out-of-order completion.

15. **[major] Unbounded parent matching permits signup-worker exhaustion.** [disposable_domain.rb:23](/Users/javi/GitHub/nondisposable-b/app/models/nondisposable/disposable_domain.rb:23): ASCII normalization accepts arbitrarily long input, and namespace construction repeatedly rebuilds suffixes. Reproduced full checks: approximately **1.9 seconds for 4 KB**, **5.9 seconds for 8 KB** of parent labels. DNS limits do not constrain submitted strings. **Fix:** check total and label lengths before any namespace traversal; add oversized ASCII-input regressions.

16. **[minor] Corroboration repeats exponential subset enumeration per domain.** [source_merge.rb:81](/Users/javi/GitHub/nondisposable-b/lib/nondisposable/source_merge.rb:81): Fourteen configured mirrors sharing one ancestor took approximately **28 seconds for only 1,000 shared domains**. A 100k list repeats that work while holding the publication lock. **Fix:** search only for a threshold-sized independent subset and cache results by voter set; add a correlated-list performance case.

Validation: 189 focused tests passed. Broader run: 465 tests, zero failures, three sandbox temporary-directory errors. Coverage was disabled; generator and file-updater suites were omitted.

**Top 3 to fix:** **2** rollback fallback; **4** SQLite serialization; **14** timestamp regression.