## [0.6.1] - 2026-10-17

### Fixed

- **A populated table is never replaced with the bundled list.** In 0.6.0, when a PRIMARY source with a bundled list (the default `disposable-email-domains`) had never been fetched successfully, `DomainListUpdater` put the list bundled with the gem in its place and published it, even over a populated table. **Who is affected:** hosts on a multi-source configuration (e.g. `Sources::RECOMMENDED`) that upgraded from 0.4/0.5. Their table is populated but has no snapshots yet. If the default source failed on the first update while another primary succeeded, the table was replaced by the bundled snapshot plus that primary, and every domain added upstream since the gem's release stopped being blocked until the next successful run. `update` returned false, but the list had already shrunk. Now the bundled stand-in is used **only on an empty table** (a fresh install). With a populated table, publishing is skipped with an error log and the table is kept as it is, until every primary has an accepted snapshot of its own. Rollback keeps its explicit bundled fallback. Reported by a codex review in CarHey.

## [0.6.0] - 2026-10-17

Ships everything listed under 0.5.0 too: 0.5.0 was never released on its own.

More than one blocklist, without trusting any of them more than it has earned. Triggered by a real incident: signups from `mail-burn.com`, a live 10-minute inbox the default list did not carry. The measurement behind every default is in `docs/evidence/2026-10-17-multi-source-measurement.md`. With the default configuration you still get the one list you had before.

### Added

- **Multiple blocklist sources** (`config.sources`, default `Nondisposable::Sources::DEFAULT`, which is today's single list). Each `Nondisposable::Source` has a `trust` (`:primary` blocks everything it lists; `:corroborating` needs `config.corroboration_threshold`, default 2, independent origins) and declares its `derived_from` lineage, so a list that copies another never counts as a second vote. Measured sources ship as constants (`DISPOSABLE_EMAIL_DOMAINS`, `FAKEFILTER`, `DISPOSABLE`, `MAILCHECKER`, `GROUNDCAT`, `WESBOS`) with licences and lineage.
- **`Nondisposable::Sources::RECOMMENDED`**: the default list plus fakefilter, both primary. +3,275 domains on 2026-10-17, none of them a known real provider. It does **not** include disposable/disposable as a primary; see the README for the 84,341 domains, real mail providers among them, that would add.
- **Source snapshots** (`nondisposable_source_snapshots`): every fetch of every source is recorded (status, time, sha256, count, list), and the stored list is rebuilt from each source's last good snapshot in one transaction, under a database advisory lock on PostgreSQL/MySQL (process lock on SQLite). Seeding takes the same lock.
- **`rails generate nondisposable:upgrade`**: an additive migration for existing installs. Until it is migrated (or after rolling it back), the updater keeps the single-source behaviour, so deploying before migrating is safe. Fresh installs get the table from `nondisposable:install`.
- **Update guards**: streamed size cap (`max_bytes`, 8 MB) and wall-clock `deadline` (30 s) per source; no redirects followed; https only; a snapshot is refused when over 1% of its lines are not domains, when it is below `minimum_count`, when it is under half the largest snapshot still retained or over three times the last good one, or when it equals a rolled-back snapshot. Counts are of unique canonical domains. Additions and removals are logged per source. Sizes count storable domains only (no junk, public suffixes or real providers). The list is never published empty; a never-fetched default source stands in its bundled list, and any other never-fetched primary blocks publishing. Rolled-back payloads stay refused permanently; failures never prune the last good snapshots.
- **Concurrency limits (documented):** on SQLite the publish lock is per process, so run the refresh job from a single runner. During a rolling deploy from 0.5, pause the refresh job until every process runs 0.6 (old processes replace the table without the lock).
- **`DomainListUpdater.reset_baseline(source_name)`**: accept a genuine upstream shrink below half of the source's high-water mark.
- **`DomainListUpdater.publish`** (rebuild from snapshots without downloading, e.g. after a config change) and **`DomainListUpdater.rollback(source_name)`** (withdraw a source's newest snapshot and republish).
- **Public Suffix List guard**: a bundled snapshot of publicsuffix.org's list (MPL 2.0, unmodified) and `Nondisposable::PublicSuffix`. Public suffixes (`com.br`, `co.uk`, `it.com`, `ddns.net`) are never stored, never accepted from `additional_domains`, and never used as a parent-match candidate, so one bad upstream line cannot block a whole namespace. Refresh with `rake nondisposable:psl:update`.
- **`data/never_disposable.txt`**: real providers and ISPs that upstream lists were found to carry, plus paid mailbox providers; unioned at runtime with `data/email_providers.txt`. Each entry protects its subdomains (`bak.rr.com` under `rr.com`). An upstream source listing one is logged as possible poisoning.
- **Privacy relays as a policy** (`config.block_privacy_relays`, default `false`, list in `data/privacy_relays.txt`): Hide My Email, DuckDuckGo, Firefox Relay, SimpleLogin/Proton Pass and addy.io are allowed even when a source lists them, or refused even when none does.
- **`Nondisposable::Domain.normalize`**: one canonical form (stripped, downcased, no trailing dot, IDN to punycode) used by the checks and by list ingestion. `Bücher.de.` and `xn--bcher-kva.de` are the same domain.

### Changed

- ⚠️ **`DisposableDomain.disposable?` / `Nondisposable.disposable?` answer `true` for a name longer than DNS allows** (`Domain.too_long?`: over 253 characters or a label over 63 once canonical, or over 1,024 code points of raw input after stripping invisible characters). Such a name can never be deliverable, and a check that keeps junk out must not call it fine. Names exactly at the limits are judged normally. The validator rejects them earlier with `invalid_tld_error_message`.
- ⚠️ **Precedence**: one table, applied both when checking and when building the list: `excluded_domains` > `never_disposable` > `additional_domains` > privacy-relay policy > sources. Before, `additional_domains` was checked first, so a domain in both `additional_domains` and `excluded_domains` was **blocked**; it is now **allowed**. `additional_domains` can no longer block a real provider listed in `never_disposable` (ignored with a warning).
- ⚠️ Two domains the default upstream list carries are **no longer blocked**: `sify.com` (Indian ISP) and `21cn.com` (China Telecom webmail).
- Entries that cannot be DNS names (labels over 63 characters, names over 253, IP addresses, HTML) are dropped from downloaded lists. The single-source path also refuses a payload with more than 1% such lines instead of storing it.
- ⚠️ **The parent-domain walk has no depth cap any more**: it checks every parent down to the registrable domain, so `a.b.c.d.tempmail.com` is blocked when `tempmail.com` is listed (or in `additional_domains`). It used to stop after 3 parent labels, which let whoever controls a listed domain escape with a fourth. Still a single `WHERE name IN (...)` query; DNS caps a name at 253 characters. It never climbs above the registrable domain, so a public suffix (`co.uk`), or a name above a wildcard suffix (`sch.uk`), can never match. `DisposableDomain::PARENT_MATCH_DEPTH` is kept but unused.
- The table is updated by writing only the difference (still in one transaction), instead of deleting and reinserting every row.

## [0.5.0] - Not released separately (shipped in 0.6.0)

Lookalike detection you can actually switch on. Replaying the 0.4.0 rule ("one edit from a provider") against the Tranco top 1M flagged 707 domains, and many are large real organisations whose staff would have been refused at signup: `ge.com`, `ml.com`, `mi.com`, `se.com` → `me.com`; `ea.com`, `aa.com` → `ya.com`; `bol.com`, `aon.com`, `uol.com` → `aol.com`; `one.com` → `ono.com`; `hive.com`, `life.com` → `live.com`; `grail.com`, `pmail.com` → `gmail.com`; `web.dev` → `web.de`; `yahoo.com.au` → `yahoo.com.ar`. Offline, nothing can tell those apart from `gmial.com` with certainty, so a guess no longer refuses anybody on its own.

### Changed

- **Behavior change for `reject_lookalike_domains = true`: it is now softer, never stricter.** Precedence, first match wins: an exact provider is accepted → an impossible TLD with a nameable correction (`gmail.con`, `gmailmcom`) is **refused**, whether or not `check_tld` is on → a reviewed typo from the new bundled `data/known_typo_domains.txt` (41 entries, e.g. `gmial.com`, `hotmial.com`, `yaho.com`) is **refused** → any other lookalike gets the same "Did you mean …?" error, but **confirmable**: it is skipped when the record says the user confirmed the address as typed. Disposable providers are still refused first, blocked TLDs are still refused after a confirmation, and a host's `additional_email_providers` outranks the known-typo list.
- **`Nondisposable.suggestion_for` suggests less, and better.** Provider names of four characters or fewer (`me`, `ya`, `aol`, `mail`, `live`…) only take edits after the name, and every edit must look like a finger slip on QWERTY (swap, dropped letter other than the first, doubled letter, extra vowel, neighbouring key, accented same key). On a retrospective 30% holdout of the labelled corpus (split chosen before tuning but committed with the tuned filters, so not pre-registered): precision 8% → 45%, recall 81% of reviewed typos. Reviewed typos are always corrected, even where the ranker alone would stay silent (`jmail.com`).
- `lookalike_distance = 0` now switches off the whole lookalike layer, known-typo list included.
- The confirmable error is added with type `:lookalike_domain` (and `suggestion:` in its details) so a form can tell it apart: `errors.of_kind?(:email, :lookalike_domain)`. The message is unchanged and still names the correction; hard lookalike errors keep their plain-message form.
- Domains are normalised the same way on every path (`Nondisposable.disposable?`, `additional_domains` / `excluded_domains`, the validator, the TLD check, suggestions, the provider and known-typo lists): stripped, lowercased, trailing dot removed, fullwidth and ideographic dots read as dots, NFKC plus the invisible characters UTS #46 drops (soft hyphen, zero-width space), unicode labels converted to punycode. `x@ｍａｉｌｉｎａｔｏｒ.com` and `x@foo．tk` no longer slip past their list entries. `user@tempmail.com.` and `user@bücher.de` (listed as `xn--bcher-kva.de`) are now caught. The local part is never touched.
- **Stored rows and 0.4.0 compatibility.** List rows are stored in the canonical (punycode) form, and lookups also match a unicode row written by 0.4.0, under the same exclusion rules (a canonical `excluded_domains` entry still wins over a legacy `bücher.de` row and its subdomains). So that a mixed-version deploy, or a rollback to 0.4.0, never silently unblocks anything, a domain added in unicode through `additional_domains` is stored **twice**: `xn--bcher-kva.de` and `bücher.de`. The row count includes these twins. ⚠️ **Rollback to 0.4.0: unicode entries from downloaded lists are stored only in punycode, so a 0.4.0 reader would not match them; no current source ships raw unicode** (all six measured lists send IDNs as `xn--`, 2026-10-17). (A 0.4.0 reader also matches `additional_domains` in memory, so the twin row matters mostly for a rollback in which the config changed too.)
- Normalisation is bounded on hostile input. NFKC runs only on names of up to 1,024 code points, and not on a run of more than 30 combining marks (not stream-safe, UAX #15). The DNS limits (253 per name, 63 per label) apply to the **normalised** result, so a valid label typed in decomposed form (`e` + combining acute) still matches.
- **Behavior change: a domain longer than DNS allows is refused** by the validator, with `invalid_tld_error_message`, whatever is switched on: over 253 characters, a label over 63 (judged on the punycode form), or over 1,024 code points before normalisation. No mail can reach such an address and no list can hold it, so it can never be "not disposable". Invisible padding (soft hyphens and the like) is stripped first, so it can neither trigger this nor hide a listed domain. Values without an `@` are still left to `format:`. `Nondisposable::Domain.too_long?(domain)` exposes the check.

### Added

- **`config.reject_lookalike_domains = :confirmable`**, the explicit name for the mode above. Strings (`"confirmable"`, `"true"`, `"false"`) are accepted for YAML/ENV config; any other value raises `ArgumentError` at boot instead of silently meaning "on".
- **`Nondisposable::ConfirmableEmail`**: `include` it and call `confirmable_email :email` to get a virtual, boolean-cast `email_lookalike_confirmed` attribute for a "Yes, my email is right" checkbox. It is reset after every save, so a later lookalike is asked about again. Without the concern, any `<attribute>_lookalike_confirmed` method returning exactly `true` works.
- **`Nondisposable::KnownTypos`** and `data/known_typo_domains.txt`: the only lookalikes refused outright, each with direct evidence that nobody has a mailbox there (redirect to the provider or the provider's own DNS, parking/for-sale network, typosquat redirect or catch-all, or registered with no MX, A or AAAA record, all lookups answered NOERROR). The evidence is in `test/fixtures/lookalike_corpus.csv` (713 rows: 44 typo, 559 real, 110 uncertain), built by `script/collect_lookalike_evidence.rb` and `script/label_lookalike_corpus.rb`; the suite fails if an entry loses its evidence row or if any non-typo row can be refused.
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
