# PR #5 — codex adversarial review, round 1

Model gpt-6.1-sol, reasoning effort high, read-only sandbox, run on 2026-10-17 against `feat/confirmable-lookalike@ff39130` (diff vs origin/main). Prompt below; output verbatim after it.

## Prompt

```text
You are an adversarial code reviewer for the Ruby gem `nondisposable` (Rails email validator). Review ONLY the diff `git diff origin/main...HEAD` in this repository (branch feat/confirmable-lookalike), ignoring docs/plans/*. Context: docs/plans/2026-10-17-lookalike-precision-and-multi-source.md §6.A is the spec. Guiding constraint: a false positive is a real person who cannot sign up; precision over recall.

Attack it for:
1. False positives: any path where a real address can be HARD-rejected (not confirmable) by the lookalike layer, the known-typo list, normalization, or the impossible-TLD path. Check data/known_typo_domains.txt entries against the evidence in test/fixtures/lookalike_corpus.csv and docs/evidence/2026-10-17-lookalike-evidence.csv; flag any entry whose evidence does not meet the bar in the file header.
2. Bypasses: ways the confirmation (Nondisposable::ConfirmableEmail / <attr>_lookalike_confirmed) lets through something it should not (disposable, impossible TLD, known typo, blocked TLD), or ways normalization lets a listed disposable domain slip through.
3. Backward-compat breaks for existing hosts upgrading from 0.4.0 (config values, error shapes, Nondisposable.disposable?, validator behaviour with reject_lookalike_domains false/true, check_tld, Ruby 3.0 / Rails 7.x compatibility).
4. Correctness of Nondisposable::Domain (punycode encoder vs RFC 3492, unicode normalisation, invalid bytes) and of the ranker (Suggestion#plausible?/finger_slip?: index errors, wrong edit classification).
5. Test gaps and evaluation honesty (holdout split, circularity, floors).

Output: terse numbered findings, each with severity [blocker|major|minor], file:line, the concrete failing input if any, and a one-line suggested fix. No praise, no summary of the change. Max ~20 findings.
```

## Output (verbatim)

1. [blocker] [email_validator.rb:67](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/email_validator.rb:67) — Confirmed `x@gnail.com` passes, but equivalent `x@gnail。com` is HARD-rejected, even with `check_tld=false`: TLD extraction ignores the new normalization. Fix: classify TLDs using the canonical domain.

2. [blocker] [known_typo_domains.txt:85](/Users/javi/GitHub/nondisposable-a/data/known_typo_domains.txt:85) — `sbcglobal.et` has `mx.sbcglobal.et`; its only justification is “Future home…” on ordinary registrar DNS. A placeholder does not meet the header’s evidence bar. Fix: remove it from hard rejection.

3. [blocker] [known_typo_domains.txt:40](/Users/javi/GitHub/nondisposable-a/data/known_typo_domains.txt:40) — `globoi.com` publishes Google Workspace and Globo corporate MX records. Provider ownership establishes ownership, not absence of employee mailboxes; confirmation cannot override rejection. Fix: keep it confirmable unless mailbox absence is established.

4. [blocker] [email_validator.rb:46](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/email_validator.rb:46) — With `excluded_domains=["bücher.de"]` and database entry `xn--bcher-kva.de`, `x@bücher.de` now gets HARD-rejected even with both opt-ins disabled. Unicode additions and stored rows conversely stop matching. Fix: canonicalize config and ingestion too, and reconcile existing rows.

5. [major] [known_typo_domains.txt:20](/Users/javi/GitHub/nondisposable-a/data/known_typo_domains.txt:20) — `ffrontier.com`, `globh.com`, `gmal.com`, `rfunbox.com`, and `hotmai.com` rely on absent A records without recorded AAAA checks; IPv6-only SMTP remains possible under [RFC 5321](https://www.rfc-editor.org/rfc/rfc5321.txt). Fix: obtain successful MX/A/AAAA evidence or remove these entries.

6. [major] [collect_lookalike_evidence.rb:65](/Users/javi/GitHub/nondisposable-a/script/collect_lookalike_evidence.rb:65) — DNS failures and negative answers both become empty arrays; the CSV cannot substantiate the header’s required successful negative lookup. Fix: preserve DNS status, exit status, and complete responses; classify failures as uncertain.

7. [major] [known_typo_domains.txt:73](/Users/javi/GitHub/nondisposable-a/data/known_typo_domains.txt:73) — `icioud.com` and `yndex.ru` are justified by unrelated redirects and no MX; recorded evidence does not establish monetization, parking, or absent SMTP fallback. Fix: document qualifying evidence or remove both.

8. [major] [known_typo_domains.txt:55](/Users/javi/GitHub/nondisposable-a/data/known_typo_domains.txt:55) — `gmil.com` and `hotmil.com` share `mail.yaxmail.net`, but raw evidence establishes neither a typo portfolio nor a catch-all service. Shared hosting alone cannot establish mailbox absence. Fix: record independent operator evidence or keep them confirmable.

9. [major] [email_validator.rb:66](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/email_validator.rb:66) — With `check_tld=true` and `.tk` blocked, confirmed `x@foo.bar．tk` passes; `x@foo.bar．con` also passes. Raw Unicode suffixes bypass canonical TLD policy. Fix: use canonical extraction for validity, blocking, and `valid_tld?`.

10. [major] [domain.rb:74](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/domain.rb:74) — Listed `mailinator.com` is bypassed by `x@ｍａｉｌｉｎａｔｏｒ.com` or `"x@maili\u00ADnator.com"`: NFC plus lowercase misses compatibility mappings and ignored characters. Fix: apply [UTS #46 mapping](https://www.unicode.org/reports/tr46/) before Punycode.

11. [minor] [confirmable_email.rb:55](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/confirmable_email.rb:55) — Save confirmed `x@gnail.com`, then assign `x@hotnail.com`: confirmation remains true and validation passes. Virtual attributes persist on the instance across saves and changes. Fix: bind confirmation to the confirmed value and clear it after saving.

12. [minor] [email_validator.rb:73](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/email_validator.rb:73) — `@gmial.com` passes because `Suggestion.for` returns nil for an empty local part, so the known-typo check never executes. Fix: enforce known-typo classification independently of suggestion availability.

13. [minor] [suggestion.rb:159](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/suggestion.rb:159) — With `additional_email_providers=["bücher.de"]`, neither `x@bucher.de` nor `x@bücehr.de` gets corrected: candidates become Punycode while edits use Unicode. Fix: retain Unicode candidates alongside canonical identities.

14. [major] [lookalike_corpus_test.rb:40](/Users/javi/GitHub/nondisposable-a/test/nondisposable/lookalike_corpus_test.rb:40) — The claimed pre-tuning holdout is unauditable: the hash/modulus rule first appears in the same commit as the tuned filters; committing labels earlier did not freeze membership. Fix: report these results as retrospective and freeze a fresh holdout before tuning.

15. [minor] [collect_lookalike_evidence.rb:95](/Users/javi/GitHub/nondisposable-a/script/collect_lookalike_evidence.rb:95) — The standalone collector calls `Array#to_set` without requiring `set`; this fails on Ruby 3.1 and affects the supported older-Ruby workflow. Fix: add `require "set"`.