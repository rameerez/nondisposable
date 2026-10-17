## [0.5.0] - Unreleased

Lookalike detection you can actually switch on. Replaying the 0.4.0 rule ("one edit from a provider") against the Tranco top 1M flagged 707 domains, and many are large real organisations whose staff would have been refused at signup: `ge.com`, `ml.com`, `mi.com`, `se.com` → `me.com`; `ea.com`, `aa.com` → `ya.com`; `bol.com`, `aon.com`, `uol.com` → `aol.com`; `one.com` → `ono.com`; `hive.com`, `life.com` → `live.com`; `grail.com`, `pmail.com` → `gmail.com`; `web.dev` → `web.de`; `yahoo.com.au` → `yahoo.com.ar`. Offline, nothing can tell those apart from `gmial.com` with certainty, so a guess no longer refuses anybody on its own.

### Changed

- **Behavior change for `reject_lookalike_domains = true`: it is now softer, never stricter.** Precedence, first match wins: an exact provider is accepted → an impossible TLD with a nameable correction (`gmail.con`, `gmailmcom`) is **refused**, whether or not `check_tld` is on → a reviewed typo from the new bundled `data/known_typo_domains.txt` (47 entries, e.g. `gmial.com`, `hotmial.com`, `yaho.com`) is **refused** → any other lookalike gets the same "Did you mean …?" error, but **confirmable**: it is skipped when the record says the user confirmed the address as typed. Disposable providers are still refused first, blocked TLDs are still refused after a confirmation, and a host's `additional_email_providers` outranks the known-typo list.
- **`Nondisposable.suggestion_for` suggests less, and better.** Provider names of four characters or fewer (`me`, `ya`, `aol`, `mail`, `live`…) only take edits after the name, and every edit must look like a finger slip on QWERTY (swap, dropped letter other than the first, doubled letter, extra vowel, neighbouring key, accented same key). On a held-out 30% of the labelled corpus: precision 9% → 48%, recall 83% of reviewed typos. Reviewed typos are always corrected, even where the ranker alone would stay silent (`jmail.com`).
- `lookalike_distance = 0` now switches off the whole lookalike layer, known-typo list included.
- The confirmable error is added with type `:lookalike_domain` (and `suggestion:` in its details) so a form can tell it apart: `errors.of_kind?(:email, :lookalike_domain)`. The message is unchanged and still names the correction; hard lookalike errors keep their plain-message form.
- Domains are normalised the same way on every path (`Nondisposable.disposable?`, the validator, suggestions, the provider and known-typo lists): stripped, lowercased, trailing dot removed, unicode labels converted to punycode. `user@tempmail.com.` and `user@bücher.de` (listed as `xn--bcher-kva.de`) are now caught. The local part is never touched.

### Added

- **`config.reject_lookalike_domains = :confirmable`**, the explicit name for the mode above. Strings (`"confirmable"`, `"true"`, `"false"`) are accepted for YAML/ENV config; any other value raises `ArgumentError` at boot instead of silently meaning "on".
- **`Nondisposable::ConfirmableEmail`**: `include` it and call `confirmable_email :email` to get a virtual, boolean-cast `email_lookalike_confirmed` attribute for a "Yes, my email is right" checkbox. Without the concern, any `<attribute>_lookalike_confirmed` method returning exactly `true` works.
- **`Nondisposable::KnownTypos`** and `data/known_typo_domains.txt`: the only lookalikes refused outright, each with direct evidence that nobody has a mailbox there (redirect to the provider or the provider's own DNS, parking/for-sale network, typosquat redirect or catch-all, or registered with neither MX nor A record). The evidence is in `test/fixtures/lookalike_corpus.csv` (713 rows: 50 typo, 559 real, 104 uncertain), built by `script/collect_lookalike_evidence.rb` and `script/label_lookalike_corpus.rb`; the suite fails if an entry loses its evidence row or if any non-typo row can be refused.
- **`Nondisposable::Domain.normalize` / `.from_email`**: the shared canonical form, including a zero-dependency RFC 3492 punycode encoder.
- `Nondisposable::Suggestion.guess(domain)`: the ranker alone, without the reviewed list.

## [0.4.0] - 2026-08-25

Catching the other kind of bad address. A disposable address is someone hiding from you; a typo is someone who wanted to reach you and can't. `user@gmail.con` isn't a throwaway — it's a real person whose account nobody will ever be able to reach, because `.con` has never existed. Both new checks are **opt-in**: upgrading this gem will not start rejecting addresses that were fine yesterday.

### Added

- **TLD validation** (`config.check_tld`, default `false`): rejects addresses whose TLD isn't in the IANA root zone. The gem now bundles a snapshot of [data.iana.org/TLD/tlds-alpha-by-domain.txt](https://data.iana.org/TLD/tlds-alpha-by-domain.txt) (~1,438 entries, ~9 KB) loaded once into a frozen `Set` — no migration, no table, no query per signup, and it can't be empty on a fresh install. A domain with no dot at all (`example@gmailmcom`) has no TLD and is rejected too; IP literals and unicode TLDs are deliberately left alone.
- **`config.additional_tlds`**: accept a TLD delegated after your installed version shipped, without waiting for a release. This is the escape hatch that keeps a stale snapshot from ever locking anyone out.
- **`Nondisposable::Tld::SPECIAL_USE`**: the RFC 6761 / RFC 2606 reserved names (`test`, `example`, `invalid`, `localhost`, `local`, `onion`). ⚠️ **Heads up when you switch `check_tld` on**: these are reserved so they can never be delegated, so they aren't in the root zone and are rejected — which is correct for a signup form, and will also turn your fixtures at `user@example.test` red. One line, scoped to where it belongs: `config.additional_tlds = Nondisposable::Tld::SPECIAL_USE if Rails.env.local?`
- **`config.blocked_tlds`** and **`config.allowed_tlds`**: refuse real TLDs you don't want (the free Freenom set `tk ml ga cf gq` is the usual reason), or invert it into an allowlist.
- **Lookalike detection**: `Nondisposable.suggestion_for("someone@gmial.com") # => "someone@gmail.com"`, matching against a bundled list of ~240 well-known providers using optimal string alignment distance, so an adjacent swap counts as the one mistake a human actually made. This catches what a TLD check structurally cannot — `.co`, `.cm` and `.om` are Colombia, Cameroon and Oman, all real. Always available, never blocks anything.
- **`config.reject_lookalike_domains`** (default `false`): turns that suggestion into a validation error naming the correction. Off by default on purpose — a suggestion is a guess about intent, and a wrong guess stops a real person signing up with their real address. `config.lookalike_distance` (default `1`) and `config.additional_email_providers` tune it.
- **`Nondisposable.valid_tld?(email)`** and **`Nondisposable.suggestion_for(email)`** as direct checks, alongside the existing `disposable?`.
- **`rake nondisposable:tlds:update`**: refreshes the bundled snapshot from IANA. A maintenance task for a checkout of this gem, not something host apps run — it refuses to overwrite a good list with an implausibly short one, writes atomically, and preserves IANA's version header (readable via `Nondisposable::Tld.version`).
- New error messages: `invalid_tld_error_message`, `blocked_tld_error_message`, `lookalike_error_message` (which interpolates `%{suggestion}`).

### Changed

- The validator now adds **at most one error** however many checks fire, and prefers the most useful message available: whenever the gem can name a correction, that phrasing wins over the generic "doesn't look like a real email address". The disposable check still takes precedence over both — a correct spelling wouldn't help a throwaway provider.

## [0.3.0] - 2026-08-09

### Added

- **Bundled seed list**: the gem now ships a snapshot of the upstream blocklist (8,201 domains) and `DomainListUpdater.seed` populates the table from it when (and only when) the table is empty. The install generator's migration seeds automatically, and `DomainListUpdater.update` falls back to seeding when the remote fetch fails against an empty table. This closes the fresh-install fail-open window where every signup passed until the first successful remote update.
- **Parent-domain matching** (`config.check_parent_domains`, default `true`): an email at `x.tempmail.com` is now blocked when `tempmail.com` is on the list. The check walks up to 3 parent labels and never matches bare TLDs. Set to `false` to restore exact-only matching.
- **Configurable failure mode** (`config.on_check_failure`, default `:allow`): controls what happens when the disposable check itself raises (e.g. database hiccup). `:allow` lets the record through with a loud error log (availability-first); `:reject` preserves the previous behavior and error message. Invalid values raise `ArgumentError`.

### Changed

- **Behavior change**: a broken check no longer rejects signups by default (previously any `StandardError` during validation added an error to the record). Set `config.on_check_failure = :reject` to keep the old fail-closed behavior.
- **Behavior change**: subdomains of listed domains are now blocked by default (see parent-domain matching above). Set `config.check_parent_domains = false` for the old exact-only behavior.
- `DomainListUpdater` now uses 10s open/read timeouts on the fetch (previously Net::HTTP's 60s defaults) so a hung connection can't block the update job.
- Domain list updates use a single bulk `insert_all` instead of per-row `create`, and report any rows skipped by the unique index instead of silently swallowing them.
- Downloaded domains are normalized before insert: whitespace/CR stripped, blank lines dropped, case-insensitive dedupe. `additional_domains` and `excluded_domains` now match case-insensitively everywhere.
- An exact entry in `excluded_domains` always wins, so a specific subdomain can be allowlisted under a listed parent domain.
- `Nondisposable.configuration` is lazily initialized: apps without an initializer no longer fail every validation with "cannot check if it's disposable".

### Removed

- Dead `require 'open-uri'` in the domain list updater.

## [0.2.1] - 2026-01-17

- Add `[nondisposable]` prefix to all logger calls for better log identification

## [0.2.0] - 2026-01-16

- Fixed `NoMethodError` when email is `"@"` or malformed (empty domain after split)
- Removed non-existent asset references from engine (`nondisposable/application.css` and `.js`)
- Removed buggy `railtie.rb` file that attempted to include a class instead of a module
- Added comprehensive Minitest 6 test suite with 256 tests and 90%+ line / branch coverage

## [0.1.0] - 2024-09-25

- Initial release
