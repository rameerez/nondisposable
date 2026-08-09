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
