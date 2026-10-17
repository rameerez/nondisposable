# PR #5 — codex adversarial review, round 3 (final verification)

Model gpt-6.1-sol, reasoning effort high, read-only sandbox, run on 2026-10-17 by the session lead against `feat/confirmable-lookalike@4afbbb9`, scoped to `git diff c2c9f49..HEAD`. Prompt below (taken from the run log); output verbatim after it.

## Prompt

```text
FINAL VERIFICATION ROUND (round 3) for rameerez/nondisposable PR #5 at HEAD 4afbbb9. Scope is strictly the fixes for round-2 findings: `git diff c2c9f49..HEAD`. Do not open new attack surfaces outside that diff; the owner caps review at this round.

Inputs: docs/reviews/2026-10-17-pr5-codex-round2.md (the round-2 findings R2-1..R2-9) and docs/reviews/2026-10-17-pr5-triage.md (claimed fixes with SHAs).

For EACH R2 finding: state VERIFIED or NOT FIXED, with the concrete input you used to check it (reproduce the round-2 input against HEAD). Then list any NEW defect INTRODUCED by the diff itself (regressions, new bypasses, new exceptions, performance cliffs, backward-compat breaks for 0.4.0 hosts, especially the R2-5 change to what the updater stores). Severity blocker/major/minor. Terse. Do not modify files. End with a one-line verdict: "ready to merge" or "not ready: <reason>".
```

## Output (verbatim)

Reviewed `c2c9f49..4afbbb9`. No files modified. Targeted suite: **154 tests, 4,672 assertions, zero failures/errors**.

| Finding | Result | Concrete check at HEAD |
|---|---|---|
| R2-1 | **VERIFIED** | `x@نامه‌ای.com` passes with row `xn--mgba3gch31f.com`; rejects with its own row `xn--mgba3gch31f060k.com`. |
| R2-2 | **VERIFIED** | Listed `mailinator.com` rejects `"x@maili\u180Enator.com"`; `"x@gmial.co\u{E0100}m"` rejects despite confirmation; blocked `.tk` rejects `"x@gmail.t\u{E0100}k"`. |
| R2-3 | **VERIFIED** | `"x@a" + "\u0315"*2000 + "\u0300"*2000 + ".com"`: normalization plus validation took approximately 14 ms initially, then under 2 ms. |
| R2-4 | **VERIFIED** | `gmal.com`, `dns_status="MX:NOERROR A:NOERROR AAAA:NOERROR"`, `resolves="no"`, `mx="mx.example.net"`: labeller aborts, status 1. |
| R2-5 | **VERIFIED** | `replace_domains(["bücher.de"])` stores `xn--bcher-kva.de`; `x@bücher.de` rejects. A preexisting `bücher.de` row also rejects that input; its Unicode exclusion permits it. |
| R2-6 | **VERIFIED** | With `additional_email_providers=["bücher.de"]`, lookalike rejection enabled and `check_tld=false`, `x@bücher.d` suggests `x@bücher.de` and rejects despite confirmation. |
| R2-7 | **VERIFIED** | `valid_tld?("x@bücher.de".b)` returns `true`; validation completes without exception. |
| R2-8 | **VERIFIED** | Rechecked the four disputed passages: README, CHANGELOG, suggestion comments and corpus-test header now qualify the results as retrospective. |
| R2-9 | **VERIFIED** | Fed the committed scan’s 707 `(rank,domain)` pairs through the script using memory-backed I/O: all 707 output rows match exactly; no gem-loading exception. |

Three defects introduced by this diff:

1. **[major] [domain.rb:108](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/domain.rb:108)** — The early length guard skips normalization of valid decompositions. Store `Domain.normalize("é"*32 + ".com")`; validate `"x@" + "e\u0301"*32 + ".com"`: **accepted**, while the composed spelling rejects. The raw 64-character label normalizes to 32 characters. `c2c9f49` canonicalizes and blocks it.

2. **[major] [disposable_domain.rb:47](/Users/javi/GitHub/nondisposable-a/app/models/nondisposable/disposable_domain.rb:47)** — Legacy lookup bypasses canonical parent exclusions. With legacy row `bücher.de`, `excluded_domains=["xn--bcher-kva.de"]`, validate `x@sub.bücher.de`: **hard-rejected**. The added Unicode candidates reintroduce the excluded parent. `c2c9f49` permits this input.

3. **[major] [domain_list_updater.rb:124](/Users/javi/GitHub/nondisposable-a/lib/nondisposable/domain_list_updater.rb:124)** — Canonical-only storage breaks **mixed-version deployments and rollback to 0.4.0**. The actual 0.4.0 reader rejects `x@bücher.de` with stored `bücher.de`; after HEAD’s `replace_domains(["bücher.de"])`, it returns **false**, silently unblocking it. Reproduced using the reader from `6032146` against the same table.

not ready: three introduced major defects in normalization, exclusions and 0.4.0 storage compatibility