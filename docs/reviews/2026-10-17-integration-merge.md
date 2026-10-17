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
