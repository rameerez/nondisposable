# PR #5 — codex adversarial review, round 2 (final freeze)

Model gpt-6.1-sol, reasoning effort high, read-only sandbox, run on 2026-10-17 by the session lead against `feat/confirmable-lookalike@c2c9f49` (diff vs origin/main). Prompt below; output verbatim after it.

## Prompt

```text
You are an adversarial code reviewer for the Ruby gem `nondisposable` (Rails email validator). This is the FINAL review round of PR #5 (branch feat/confirmable-lookalike, frozen at HEAD). Review the full diff `git diff origin/main...HEAD`, ignoring docs/plans/* and docs/reviews/* except as context. Spec: docs/plans/2026-10-17-lookalike-precision-and-multi-source.md §6.A. Guiding constraint: a false positive is a real person who cannot sign up; precision over recall.

Round 1 found 15 issues; they and their claimed fixes are listed in docs/reviews/2026-10-17-pr5-triage.md (fix commits 6fc839b and bc388f5; see `git show 6fc839b bc388f5`). Do two things:

A. VERIFY each round-1 fix marked "fixed": is it actually correct and complete? Give a concrete failing input for any that is not. Also challenge the "rejected" (#13) and "disclosed" (#14) decisions if you think they are wrong.

B. ATTACK the code added after round 1 specifically: Domain.unicode/normalize (NFKC, IGNORED set, the 253/63 length guard), Tld.normalize delegating to Domain.unicode, DisposableDomain normalising additional/excluded, the validator's KnownTypos fallback for an empty local part, ConfirmableEmail's after_save reset, the collector's dig parsing (dns_status, AAAA), and the labeller's undeliverable guard. Look for false positives (hard rejects of real addresses), bypasses (a listed disposable domain or a known typo slipping through; confirmation letting through something it should not), backward-compat breaks for 0.4.0 hosts, crashes/raises inside the validator, performance on hostile input, and test gaps.

Output: terse numbered findings, each with severity [blocker|major|minor], file:line, concrete failing input if any, and a one-line suggested fix. Start with a short "Round-1 fix verification" list (one line per round-1 #: OK or the problem). No praise. Max ~20 findings.
```

## Output (verbatim)

**Round-1 fix verification**

- #1: OK.
- #2: OK.
- #3: OK.
- #4: Incomplete: stored Unicode rows still bypass checking; finding 5.
- #5: OK for the five recorded domains’ AAAA evidence.
- #6: Lookup-failure separation fixed; the new nondeliverability guard is incomplete; finding 4.
- #7: OK.
- #8: OK.
- #9: OK.
- #10: Incomplete: ignored mappings are missing, and joiner removal changes domain identity; findings 1–2.
- #11: OK across successful saves.
- #12: OK.
- #13: Rejection overlooks an invalid-TLD rejection bypass; finding 6.
- #14: Disclosure leaves contradictory preregistration claims in shipped files; finding 8.
- #15: OK.
- B-1: Incomplete: expensive normalization precedes the length guard; finding 3.

1. **[blocker] [lib/nondisposable/domain.rb:47](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/domain.rb:47)** — Removing ZWNJ/ZWJ merges distinct valid domains. With DB row `xn--mgba3gch31f.com`, `x@نامه‌ای.com` is hard-rejected although its IDNA2008 identity is `xn--mgba3gch31f060k.com`; listing the latter instead lets its Unicode spelling bypass checking. These identities are explicitly distinguished in [UTS #46](https://www.unicode.org/reports/tr46/#Deviations). **Fix:** preserve contextual joiners using nontransitional mapping.

2. **[major] [lib/nondisposable/domain.rb:47](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/domain.rb:47)** — The ignored set omits U+180E, U+180F and U+E0100–E01EF. Reproduced: `"x@maili\u180Enator.com"` bypasses listed `mailinator.com`; `"x@gmial.co\u{E0100}m"` bypasses KnownTypos; `"x@gmail.t\u{E0100}k"` bypasses blocked `.tk`. These are ignored mappings, not omitted validity checks. [Unicode mapping table](https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt). **Fix:** implement the complete ignored mapping and cover all three checking paths.

3. **[major] [lib/nondisposable/domain.rb:64](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/domain.rb:64)** — The length guard runs after expensive NFKC processing. Input `"x@a" + "\u0315"*2000 + "\u0300"*2000 + ".com"` takes approximately 1.8 seconds per normalization here; validation can normalize it repeatedly, even with typo checks disabled. The existing oversized-CJK test misses combining-mark reordering. **Fix:** bound raw input before Unicode normalization.

4. **[major] [script/label_lookalike_corpus.rb:154](/Users/javi/GitHub/nondisposable-a/script/label_lookalike_corpus.rb:154)** — The undeliverable guard ignores `mx`. Changing `gmal.com`’s evidence to contain a working remote MX while retaining `dns_status="MX:NOERROR A:NOERROR AAAA:NOERROR"` and `resolves="no"` still emits `typo`; remote SMTP delivery requires no apex address. **Fix:** require absent MX, or separately prove every advertised MX target unusable; add this regression case.

5. **[major] [app/models/nondisposable/disposable_domain.rb:24](/Users/javi/GitHub/nondisposable-a/app/models/nondisposable/disposable_domain.rb:24)** — Lookup canonicalization still disagrees with ingestion and existing rows. Reproduced: `DomainListUpdater.send(:replace_domains, ["bücher.de"])` stores `bücher.de`, then `Nondisposable.disposable?("x@bücher.de")` returns `false`. Existing 0.4.0 Unicode rows have the same regression. **Fix:** canonicalize ingestion and reconcile existing stored names.

6. **[major] [lib/nondisposable/suggestion.rb:159](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/suggestion.rb:159)** — Rejected #13 costs more than a hint: with `additional_email_providers=["bücher.de"]`, `reject_lookalike_domains=true`, and `check_tld=false`, `x@bücher.d` passes. Verified 0.4.0 suggested `x@bücher.de` and rejected it. Punycode candidates cannot match Unicode keystrokes. **Fix:** retain Unicode ranking targets alongside canonical exemption identities.

7. **[minor] [lib/nondisposable/tld.rb:165](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/tld.rb:165)** — `Nondisposable.valid_tld?("x@bücher.de".b)` now raises `Encoding::CompatibilityError`; 0.4.0 returns `true`. `Domain.unicode` lacks the encoding protection provided by `normalize`. **Fix:** handle valid UTF-8 bytes supplied with binary encoding and define a nonraising fallback for unreadable input.

8. **[major] [test/nondisposable/lookalike_corpus_test.rb:18](/Users/javi/GitHub/nondisposable-a/test/nondisposable/lookalike_corpus_test.rb:18)** — Despite #14’s disclosure, the shipped test still explicitly claims membership was “fixed before any filter was written”; `suggestion.rb` calls it untouched, while README/CHANGELOG advertise held-out results without the retrospective qualification. **Fix:** correct every claim and freeze a fresh holdout before further tuning.

9. **[minor] [docs/evidence/tranco_lookalike_scan.rb:1](/Users/javi/GitHub/nondisposable-a/docs/evidence/tranco_lookalike_scan.rb:1)** — The reproduction script loads the author’s absolute checkout and requires only `suggestion`; against this HEAD its first correction raises `NameError` for `Domain`. Loading current dependencies would also use the changed ranker rather than reproduce the original 707 hits. **Fix:** use repository-relative dependencies and explicitly pin the baseline scan algorithm.