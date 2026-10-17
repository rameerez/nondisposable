# Integration merge: PR #5 (0.5.0) + PR #6 (0.6.0)

Branch `integrate/0.5-0.6`:
- `origin/main`;
- merged with PR #5 `feat/confirmable-lookalike` (merge 23c36c7, head 4afbbb9);
- then merged with PR #6 `feat/multi-source` (head 5fd7369).

Neither feature branch was modified. Only the PR #6 merge conflicted. "Ours" is
the integration branch (main + #5); "theirs" is #6.

## Conflicts

| File | Resolution | Why |
|---|---|---|
| `CHANGELOG.md` | Both entries: `## [0.6.0] - Unreleased` (#6) above `## [0.5.0] - Unreleased` (#5), then 0.4.0 unchanged. | Release order. Each entry is self-contained. |
| `lib/nondisposable.rb`, requires | Union: #5's (`domain`, `known_typos`, `confirmable_email`) plus #6's (`public_suffix`, `precedence`, `source`, `source_merge`, `source_fetcher`, `public_suffix_list_updater`). | Both sets are needed. Load order is safe: `precedence`/`source` only reference `Domain`, which loads first. |
| `lib/nondisposable.rb`, `Nondisposable.disposable?` | Took #5's body (`Domain.from_email(email, unicode: true)`). | #6's version was the pre-0.5 split. `DisposableDomain.disposable?` in #6 normalizes its argument and also needs the unicode spelling to match legacy rows, which is exactly what #5 passes. The Configuration hunks merged cleanly into the union: #5's `LOOKALIKE_MODES` and validating `reject_lookalike_domains=` setter; #6's `sources`, `corroboration_threshold`, `block_privacy_relays`. |
| `app/models/nondisposable/disposable_domain.rb` | Took #6's file whole. | #6 already contains every behaviour #5 added, so nothing was lost (checked against #5's version line by line): `Domain.normalize` of the argument; refusing a non-UTF-8 domain; host lists normalized (via `Precedence`'s `configured_set`, which uses `Domain.normalize`); rows stored in unicode by 0.4.0 still matching, with exclusions honoured (legacy candidates are kept only when their normalized form is still an eligible candidate). #5's depth-3 walk and its additional-before-excluded order are superseded by #6's uncapped registrable walk and precedence table (E1, and §6 of the plan). #5's tests for these behaviours pass unchanged. |
| `lib/nondisposable/domain_list_updater.rb` | Took #6's file whole, plus one change in `lib/nondisposable/precedence.rb` (not a conflict). | #6's snapshot/merge design replaces #5's `replace_domains`/`normalize`. To keep #5's R2-5 rule ("store `Domain.normalize`d names") on EVERY write path whoever the caller is, `Precedence.filter` now normalizes each entry itself. Every write goes through it: fetch → `publish_domains`, `seed!`, the bundled stand-in for a primary, the rollback fallback, and the single-source path. Before this, those paths relied on their callers having used `Source.parse`. |

## Non-conflict adjustment

- `test/nondisposable/domain_test.rb` (#5): `test_a_unicode_entry_from_a_downloaded_list_is_stored_as_lookups_ask_for_it`
  called the private `DomainListUpdater.replace_domains`, which #6 removed. It
  now drives the same behaviour through the public path (`stub_domain_list("bücher.de\n")` + `update`).
  Its assertions are unchanged: the row is stored as `xn--bcher-kva.de` and the
  unicode address is still disposable.

## Verification

- `bundle exec rake test`: 589 tests, 0 failures, 0 errors; 98.28% line / 94.7% branch coverage.
- Appraisals `gemfiles/rails_7.2`, `rails_8.0`, `rails_8.1`: 589 tests, 0 failures each.
- `lib/nondisposable/domain.rb` is identical to both branches (sha256 c62066dbeb89249a…).

## Round-3 fixes on this branch

PR #6's round 3 (`docs/reviews/2026-10-17-pr6-codex-round3.md` on
feat/multi-source) found four majors introduced by its round-2 fixes. They are
fixed here, on top of A's 710caaa, which carries domain.rb's R3-2 ordering and
the 0.4.0 twin rows (`legacy_spellings`):

| # | Fix | Regression |
|---|---|---|
| R3-1 | `high_water_column?` checks `SourceSnapshot.column_names`. Without the column, nothing is written to it, the shrink guard falls back to retained snapshots, and a warning is logged once per process. Still ONE create migration (the schema is unreleased). | `test_a_table_without_high_water_count_still_refreshes` |
| R3-2 | A's domain.rb (710caaa): strip ignorables → 1,024 cap → NFKC → 253/63. | A's domain_test.rb round-3 section |
| R3-3 | Removed the raw 1,024 return in `DisposableDomain.disposable?`. Length is judged only on `Domain.normalize`'s output (≤ 253). `MAX_INPUT_LENGTH` is kept as an alias of `Domain::MAX_RAW_LENGTH`. | `test_soft_hyphen_padding_cannot_hide_a_listed_domain` (`"­" * 1013 + "tempmail.com"`) |
| R3-4 | `storable_count` = `Precedence.filter(domains, host_policy: false)`. It ignores every host setting and always drops relays, so counts are comparable across policy changes. `reset_baseline` recomputes `domain_count`/`high_water_count` from the latest payload. | `test_a_relay_policy_flip_does_not_trip_the_shrink_guard` (100 relays + 20, flip, reset, accept), `test_reset_baseline_recomputes_from_the_payload` |

Verification (clean checkout of the commit): 597 tests, 0 failures (98.31% line / 94.42% branch), plus the
rails_7.2, rails_8.0 and rails_8.1 appraisals: 597 tests, 0 failures each.

## Over-length domains (lead decision, 2026-10-17)

After A's f44536e (the validator rejects over-length domains, plus the new
`Domain.too_long?`), direct callers of `DisposableDomain.disposable?` and
`Nondisposable.disposable?` now get `true` when `Domain.too_long?(domain)`:
such a name can never be deliverable, and a "keep junk out" check must not
answer "fine". The check runs before any normalization work or lookup.
`MAX_DOMAIN_LENGTH` (unreleased) is removed. Three tests that asserted `false`
were flipped to the decision: one in A's domain_test, two in the round-2
regressions. `test_names_longer_than_dns_allows_are_disposable` covers over-253,
a label over 63, and names exactly at both limits (judged normally).
