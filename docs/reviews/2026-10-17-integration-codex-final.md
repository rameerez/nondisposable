One **major** remains: PR #5 R3-3 is only partially fixed. Downloading `"bücher.de\n"` stores only `xn--bcher-kva.de`; the actual 0.4.0 reader then allows `x@bücher.de`. `Source.parse` discards the Unicode spelling before `legacy_spellings` sees it. Host additions correctly receive both rows.

| Round-3 finding | Result | Concrete reproduction |
|---|---|---|
| #5 R3-1 | **VERIFIED** | Store normalized `"é"*32 + ".com"`; `"x@" + "e\u0301"*32 + ".com"` now rejects. |
| #5 R3-2 | **VERIFIED** | Legacy row `bücher.de`, exclusion `xn--bcher-kva.de`: `x@sub.bücher.de` passes. |
| #5 R3-3 | **NOT FIXED — major** | Downloaded `bücher.de`: current reader returns `true`; 0.4.0 reader returns `false`. `additional_domains=["Bücher.de"]` correctly stores twins. |
| #6 R3-1 | **VERIFIED** | Remove `high_water_count`: 100-domain refresh succeeds; 40-domain refresh rejects against retained baseline 100; warning logged. |
| #6 R3-2 | **VERIFIED** | Same composed/decomposed input as #5 R3-1: equal normalization, both blocked. |
| #6 R3-3 | **VERIFIED** | `"\u00ad"*1013 + "tempmail.com"` normalizes correctly; both disposable APIs return `true`. |
| #6 R3-4 | **VERIFIED** | 100 relay subdomains + 20 ordinary domains count as 20 under either policy. Inject stale baseline 120; reset recomputes 20 and refresh succeeds. |

Merge resolution: no unintended loss found. Precedence remains exclusions → never-disposable → additions → relay policy → sources. Canonicalization covers every updater write path; legacy lookup respects canonical exclusions. The validating `reject_lookalike_domains=` setter survives, including string modes and invalid-value rejection.

Additional checks: over-length labels/names return `true` through both disposable APIs and fail validation with the invalid-domain message. Exactly 63-character labels and 253-character names pass normally. `host_policy:false` ignores exclusions/additions and always drops relays.

Host smoke, using stubbed downloads: no crashes or false positives for `gmail.com`, `outlook.es`, `bbc.co.uk`, `alumnos.upm.es`, `ge.com`, or `uol.com` across default → RECOMMENDED → confirmable. `gnail.com` saves after confirmation and resets confirmation; `mailinator.com` stays blocked. **`mail-burn.com` passes**—the documented source-coverage gap; adding it to `additional_domains` blocks it. Live source payloads were not tested.

212 targeted tests, 1,502 assertions, zero failures/errors. No files modified.

not ready: PR #5 R3-3 still permits downloaded Unicode domains after rollback to 0.4.0