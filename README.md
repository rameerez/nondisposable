# 🗑️ `nondisposable` - Block disposable email addresses from signing up to your Rails app

[![Gem Version](https://badge.fury.io/rb/nondisposable.svg)](https://badge.fury.io/rb/nondisposable) [![Build Status](https://github.com/rameerez/nondisposable/workflows/Tests/badge.svg)](https://github.com/rameerez/nondisposable/actions)

> [!TIP]
> **🚀 Ship your next Rails app 10x faster!** I've built **[RailsFast](https://railsfast.com/?ref=nondisposable)**, a production-ready Rails boilerplate template that comes with everything you need to launch a software business in days, not weeks. Go [check it out](https://railsfast.com/?ref=nondisposable)!

`nondisposable` is a Ruby gem that prevents users from signing up to your Rails app with disposable email addresses.

Simply add to your User model:

```ruby
validates :email, nondisposable: true
```

That's it! You're done.

The gem also provides a job you can run daily to keep your disposable domain list up to date.

It can also catch the other kind of bad address — the typo. `user@gmail.con` isn't a throwaway, it's a real person whose account nobody will ever be able to reach, because `.con` doesn't exist. Two opt-in checks:

```ruby
Nondisposable.configure do |config|
  config.check_tld = true                # reject TLDs that aren't in the IANA root zone
  config.reject_lookalike_domains = true # and addresses one keystroke from a real provider
end
```

See [Catching typos](#catching-typos).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'nondisposable'
```

And then execute:

```bash
bundle install
```

After installing the gem, run the installation generator:

```bash
rails generate nondisposable:install
```

This will create the necessary migration file, initializer, and a job for scheduled updates. Run the migration:

```bash
rails db:migrate
```

The migration also seeds the table from a snapshot of the disposable-domain list bundled with the gem, so your app is protected immediately. To fetch the very latest list, run:

```ruby
Nondisposable::DomainListUpdater.update
```

## Usage

To use `nondisposable` in your models, simply add the validation:

```ruby
class User < ApplicationRecord
  validates :email, nondisposable: true
end
```

You can customize the error message:
```ruby
class User < ApplicationRecord
  validates :email, nondisposable: { message: "is a disposable email address, please use a permanent email address." }
end
```

The validation works seamlessly with other Rails validations:
```ruby
class User < ApplicationRecord
  validates :email,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            nondisposable: true
end
```

If you're validating a different attribute name:
```ruby
class User < ApplicationRecord
  validates :backup_email, nondisposable: true
end
```

### Configuration

You can customize the gem's behavior by creating an initializer:

```ruby
# config/initializers/nondisposable.rb

Nondisposable.configure do |config|
  config.error_message = "provider is not allowed. Please use a non-disposable email address."
  config.additional_domains = ['custom-disposable-domain.com']
  config.excluded_domains = ['false-positive-domain.com']

  # What to do when the disposable check itself fails (e.g. database hiccup):
  #   :allow  - let the signup through and log an error (availability-first, default)
  #   :reject - block the signup with a validation error (fail closed)
  config.on_check_failure = :allow

  # Also match parent domains: an email at x.tempmail.com is blocked when
  # tempmail.com is on the list. Set to false for exact matches only.
  config.check_parent_domains = true

  # --- Where the blocklist comes from (see "Blocklist sources") ---
  config.sources = Nondisposable::Sources::DEFAULT  # or ::RECOMMENDED
  config.corroboration_threshold = 2                # independent lists a :corroborating entry needs
  config.block_privacy_relays = false               # Hide My Email, DuckDuckGo, SimpleLogin, addy.io…

  # --- Catching typos (both OFF by default) ---

  # Reject addresses whose TLD isn't in the IANA root zone: gmail.con, outlook.ed
  config.check_tld = true
  config.additional_tlds = []                # accept a TLD newer than this gem
  config.blocked_tlds = %w[tk ml ga cf gq]   # refuse real TLDs you don't want
  config.allowed_tlds = nil                  # or allowlist: %w[es com] rejects everything else

  # Reject addresses one keystroke from a well-known provider: gmail.co, gmial.com
  config.reject_lookalike_domains = false
  config.lookalike_distance = 1              # edits that still count as a typo
  config.additional_email_providers = []     # your own domains / regional providers

  config.invalid_tld_error_message = "doesn't look like a real email address"
  config.blocked_tld_error_message = "domain ending is not allowed"
  config.lookalike_error_message = "looks like a typo. Did you mean %{suggestion}?"
end
```

#### Parent domain matching

With `check_parent_domains` enabled (the default since 0.3.0), `user@x.tempmail.com` is blocked when `tempmail.com` is on the list. The check walks every parent down to the registrable domain (`a.b.c.d.tempmail.com` → … → `d.tempmail.com` → `tempmail.com`), however deep, and never matches against a public suffix like `com` or `co.uk`. All candidates are checked in a single indexed query. (Until 0.6.0 the walk stopped after 3 parent labels, so whoever controlled a listed domain could escape it with a fourth.)

Since 0.6.0 the walk also never matches a **public suffix** — `co.uk`, `com.br`, `github.io` — using a snapshot of the [Public Suffix List](https://publicsuffix.org) bundled with the gem (no runtime dependency, no network). Upstream lists really do carry entries like `it.com` and `ddns.net`, under which anybody can register a name; one such line would otherwise refuse every unrelated company below it. Public suffixes are also never stored and never accepted from `additional_domains`.

If you need to allowlist a specific subdomain under a listed parent, add the exact subdomain to `excluded_domains`; an exact exclusion always wins. Excluding a parent domain also unblocks its subdomains (unless a more specific subdomain is itself listed).

#### Who wins when lists disagree

One precedence table, applied both when an address is checked and when the stored list is built. Top wins:

| # | List | Effect |
|---|---|---|
| 1 | `config.excluded_domains` (yours) | allowed |
| 2 | `data/never_disposable.txt` (bundled: real providers and ISPs, plus `data/email_providers.txt`) | allowed, including subdomains |
| 3 | `config.additional_domains` (yours) | blocked |
| 4 | `data/privacy_relays.txt` (bundled) | `config.block_privacy_relays` decides |
| 5 | the upstream sources | blocked |

> [!IMPORTANT]
> **Changed in 0.6.0:** before, `additional_domains` was checked first, so a domain in both `additional_domains` and `excluded_domains` was blocked. Now your exclusion wins. And because row 2 outranks row 3, `additional_domains` can no longer block a real provider such as `gmail.com` or `mail.ru` (it is ignored with a warning in the log): that list is for throwaway domains the upstream lists missed, and refusing a whole real provider is a business rule that belongs in your own validation, where it can tell the user why.

Row 2 is why upgrading also **unblocks** two domains the default upstream list carried on 2026-10-17: `sify.com` (an Indian ISP) and `21cn.com` (China Telecom's webmail). A false positive is a real person who cannot sign up; if you find one, it belongs in `never_disposable.txt` (open a PR) or in your `excluded_domains`.

#### Failure mode

By default (`on_check_failure = :allow`), if the disposable check raises — say, the database is briefly unavailable — the signup goes through and an error is logged. This is availability-first: a broken check should not lock everyone out of signup. If you'd rather fail closed (reject signups whenever the check cannot run, as versions before 0.3.0 did), set `config.on_check_failure = :reject`.

### Catching typos

A disposable address is someone hiding from you. A typo is someone who wanted to reach you and won't be able to. Both leave you with a useless row in the users table, so `nondisposable` can catch both — but the typo checks are **opt-in**, because upgrading a gem should never start rejecting addresses that were fine yesterday.

#### `config.check_tld` — is that a real domain ending?

Every TLD that exists is in the [IANA root zone database](https://data.iana.org/TLD/tlds-alpha-by-domain.txt), and the gem ships a snapshot of it (~1,438 entries, about 9 KB, loaded once into a frozen `Set`). `.con` has never been in it, and never will be.

```ruby
config.check_tld = true

Nondisposable.valid_tld?("user@gmail.com")   # => true
Nondisposable.valid_tld?("user@gmail.con")   # => false
Nondisposable.valid_tld?("example@gmailmcom") # => false  (no TLD at all)
```

Details worth knowing:

- **No dot, no TLD.** `example@gmailmcom` models a typo observed in production: the dot was missed entirely. A domain with no TLD can't end in a real one, so it's rejected. If your app accepts single-label intranet addresses like `you@localhost`, leave this off for that model.
- **IP literals are left alone.** `user@192.168.0.1` and `user@[10.0.0.1]` are a format question, and a TLD check has no business answering it. Pair with `format:` if you care.
- **Unicode TLDs are never rejected.** IANA lists internationalised TLDs in punycode (`XN--FIQS8S`), and converting `例え.テスト` to that form needs an IDN library this gem deliberately doesn't depend on. Rather than reject every unicode address, it declines to judge them. Punycode-form addresses — what mail clients actually send — are checked normally.
- **A stale snapshot can't trap you.** If ICANN delegates a TLD after your gem version shipped, `config.additional_tlds = %w[newtld]` accepts it immediately, with no release to wait for.

> [!IMPORTANT]
> **`.test` and `.example` are rejected, and that will turn your test suite red.**
>
> RFC 6761 and RFC 2606 reserve `test`, `example`, `invalid` and `localhost` precisely so they can never be delegated — which is why they aren't in the root zone, and why your fixtures live at `user@example.test` in the first place. Rejecting them is right for a signup form (no human types `me@home.test`, and mail could never be delivered there), but it's a configuration question, not a bug:
>
> ```ruby
> # config/initializers/nondisposable.rb
> config.additional_tlds = Nondisposable::Tld::SPECIAL_USE if Rails.env.local?
> ```
>
> Scope it to your non-production environments, so production still refuses an address nobody could ever answer.

`blocked_tlds` refuses TLDs that are perfectly real but that you'd rather not see — the historically free Freenom set (`tk`, `ml`, `ga`, `cf`, `gq`) is the usual suspect. `allowed_tlds` inverts it into an allowlist; be careful, `%w[es]` turns away every `.com` customer you have.

#### `config.reject_lookalike_domains` — did they mean gmail.com?

A TLD check structurally **cannot** catch the most common typos, because `.co` (Colombia), `.cm` (Cameroon) and `.om` (Oman) are all real, delegated TLDs. `user@gmail.co` is a well-formed address at a real TLD and still almost always a finger that slipped off the `m`.

So the second check asks a different question: is this domain one edit away from a well-known provider, while not being one itself?

```ruby
Nondisposable.suggestion_for("someone@gmial.com") # => "someone@gmail.com"
Nondisposable.suggestion_for("someone@gmail.co")  # => "someone@gmail.com"
Nondisposable.suggestion_for("someone@gmail.com") # => nil
Nondisposable.suggestion_for("someone@mail.com")  # => nil  (a real provider)
```

`suggestion_for` is always available and **never blocks anything** — show it as a hint and let the human decide. That's the gentler way to use this, and the one to reach for first:

```erb
<% if (did_you_mean = Nondisposable.suggestion_for(@user.email)) %>
  <p>Did you mean <%= did_you_mean %>?</p>
<% end %>
```

The matching uses optimal string alignment distance rather than plain Levenshtein, so an adjacent swap counts as the one mistake a human actually made: `gmial.com` is distance 1, not 2.

One edit is not enough to tell a typo from a real domain, though. Replayed against the [Tranco](https://tranco-list.eu) top 1M, "one edit from a provider" flags **707** domains, and many of them are large real organisations:

- `ge.com` (General Electric), `ml.com` (Merrill Lynch), `mi.com` (Xiaomi), `se.com` (Schneider Electric) → `me.com`
- `ea.com` (Electronic Arts), `aa.com` (American Airlines) → `ya.com`
- `bol.com`, `aon.com`, `uol.com` (a major Brazilian mail provider) → `aol.com`
- `one.com` → `ono.com`; `hive.com`, `life.com` → `live.com`; `grail.com`, `pmail.com` → `gmail.com`
- `web.dev` → `web.de`; `yahoo.com.au` → `yahoo.com.ar`

So since 0.5.0 suggestions are filtered before anyone sees them: a provider name of four characters or fewer (`me`, `ya`, `aol`, `mail`, `live`…) only takes edits after the name (`me.cmo` yes, `ge.com` no), and every edit has to look like a finger — a swap, a dropped letter (not the first), a doubled letter, an extra vowel, a neighbouring key on QWERTY, or the same key with an accent. A letter from across the keyboard (`grail`, `pmail`, `.au` for `.ar`) is a different word, not a slip. On a 30% holdout of the labelled corpus that keeps 13 of 16 reviewed typos and raises precision from 8% to 45% — measured retrospectively: the split was chosen before tuning but only committed with the tuned filters, so treat it as an estimate, not a pre-registered result. Better, still a guess — which is why a guess never refuses anyone on its own.

#### `reject_lookalike_domains`: hard for known typos, confirmable for everything else

```ruby
config.reject_lookalike_domains = :confirmable # `true` means the same thing
```

| The domain is… | Example | Result |
|---|---|---|
| an exact provider (bundled or `additional_email_providers`) | `gmail.com`, `mail.com` | accepted |
| an impossible TLD with a nameable correction (`check_tld` on or not) | `gmail.con`, `gmailmcom` | **refused**: "Did you mean …gmail.com?" |
| a reviewed typo in [`data/known_typo_domains.txt`](data/known_typo_domains.txt) | `gmial.com`, `hotmial.com`, `yaho.com` | **refused**: "Did you mean …?" |
| any other lookalike the ranker suggests | `gnail.com` | **confirmable**: same message, unless the user confirmed the address |
| anything else | `ge.com`, `yahoo.com.au` | accepted |

A disposable provider is still refused first, and a blocked TLD is still refused after a confirmation. A host's `additional_email_providers` outranks the known-typo list.

The known-typo list is short (41 entries) on purpose. An entry needs direct evidence that nobody has a mailbox there — a redirect to the provider or the provider's own DNS (`yaho.com`, `homail.com`), a parking or for-sale network (`gamail.com`, `hotmial.com`), a typosquat redirect or catch-all (`gmial.com`, `gmali.com`), or a registered domain with no MX, A or AAAA record (`gmal.com`). "No MX" alone is not enough: SMTP falls back to the A record. The evidence for every entry is in `test/fixtures/lookalike_corpus.csv`, and the suite fails if an entry loses it.

**Confirmable means the user can say "yes, this address is right".** Give the model somewhere to put that answer:

```ruby
class User < ApplicationRecord
  include Nondisposable::ConfirmableEmail
  confirmable_email :email # adds a virtual email_lookalike_confirmed attribute

  validates :email, nondisposable: true
end
```

```erb
<%# Only when the confirmable error is showing: %>
<% if @user.errors.of_kind?(:email, :lookalike_domain) %>
  <%= f.check_box :email_lookalike_confirmed %>
  <%= f.label :email_lookalike_confirmed, "Yes, my email address is right" %>
<% end %>
```

Permit `:email_lookalike_confirmed` in your strong parameters. It's virtual — never persisted, and reset after every save — so it answers for one save; the error also carries the suggestion in `errors.details[:email]` (`suggestion:`). No concern needed if you'd rather wire it yourself: the validator only looks for a method named `<attribute>_lookalike_confirmed` that returns exactly `true`.

> [!WARNING]
> Without the checkbox, a confirmable error has no way past it — a real `gnail.com` user would be stuck. Wire the confirmation before you switch this on, or keep using `suggestion_for` as a hint only.

Before 0.5.0, `true` refused every lookalike outright. If you set it, upgrading makes it **softer**, never stricter: reviewed typos and impossible TLDs are still refused, every other lookalike becomes confirmable, and many of the old matches (`ge.com`, `bol.com`) are no longer suggested at all.

Matching stops at **one** edit by default (`lookalike_distance`; 2 is coarser and documented as risky, 0 switches the whole layer off, list included). Add anything we've missed with `config.additional_email_providers`; doing so both makes it a suggestion candidate and stops its users being told they mistyped.

#### How the two combine

At most one error is added, however many checks fire — and whenever the gem can name a correction, that phrasing wins:

| Address | `check_tld` only | with `reject_lookalike_domains` |
|---|---|---|
| `user@gmail.con` | "looks like a typo. Did you mean user@gmail.com?" | same |
| `user@zzz.con` | "doesn't look like a real email address" | same |
| `user@gmail.co` | accepted | "looks like a typo. Did you mean user@gmail.com?" (a reviewed typo: refused) |
| `user@gnail.com` | accepted | same message, confirmable |
| `user@ge.com` | accepted | accepted |
| `user@tempmail.com` | "provider is not allowed" | same |

"Doesn't look like a real email address" is true but useless when we know what they meant, so a nameable correction always outranks the generic message.

### Direct Check

You can also check if an email is disposable directly:

```ruby
Nondisposable.disposable?('user@example.com') # => false
Nondisposable.disposable?('user@disposable-email.com') # => true
Nondisposable.valid_tld?('user@example.con')  # => false
Nondisposable.suggestion_for('user@gmial.com') # => "user@gmail.com"
```

Every check compares domains in one canonical form — lowercased, without a trailing dot, unicode labels converted to punycode, so `user@Bücher.DE.` and `user@xn--bcher-kva.de` get the same verdict. The local part is never touched (case and `+tags` are the user's business). The same normalisation is available as `Nondisposable::Domain.normalize(domain)` and `Nondisposable::Domain.from_email(email)`.

## Updating disposable domains

To manually update the list of disposable domains, run:

```ruby
Nondisposable::DomainListUpdater.update
```

The fetch uses 10-second open/read timeouts and replaces the whole table atomically (see [Blocklist sources](#blocklist-sources) for how several lists are merged and guarded). If the remote fetch fails and your table is empty (e.g. a fresh install without network access), the updater automatically seeds from the blocklist snapshot bundled with the gem so you're never left unprotected; you can also trigger that explicitly with `Nondisposable::DomainListUpdater.seed` (it only seeds an empty table, and never overwrites existing data).

It's important you keep your disposable domain list up to date. `nondisposable` will read from the latest version of the [`disposable-email-domains`](https://github.com/disposable-email-domains/disposable-email-domains) list, which is typically updated every few days.

For this, `nondisposable` provides you with an Active Job (`DisposableEmailDomainListUpdateJob`) that you can use to schedule daily updates. How you do that, exactly, depends on the queueing system you're using.

If you're using `solid_queue` (the Rails 8 default), you can easily add it to your schedule in the `config/recurring.yml` file like this:
```yaml
production:
  refresh_disposable_domains:
    class: DisposableEmailDomainListUpdateJob
    queue: default
    schedule: every day at 3am US/Pacific
```

## Blocklist sources

Out of the box the gem uses the one list it always has, [`disposable-email-domains`](https://github.com/disposable-email-domains/disposable-email-domains). Upgrading changes nothing. You can add more:

```ruby
config.sources = Nondisposable::Sources::RECOMMENDED
```

`RECOMMENDED` adds [fakefilter](https://github.com/7c/fakefilter), which watches temp-mail generators directly. On 2026-10-17 it added **3,275 domains** (13,168 in total, against 9,893), and none of them was a known real provider.

> [!NOTE]
> **More lists do not catch fresh burners.** `mail-burn.com`, the domain that prompted this feature, was live and handing out inboxes on 2026-10-17. Of the measured lists only disposable/disposable carried it, from its own crawl. groundcat had it too, but only because it copies disposable/disposable. That is **one origin**, and corroboration rightly refuses to count copies, so no precision-first combination of public lists blocks it. A fresh burner shows up in one crawler's list first. Until a list exists that publishes *evidence* for each fresh domain, block a domain you have verified yourself with `config.additional_domains`, and send it upstream.

### Trust and lineage

Every source is a `Nondisposable::Source` with a `trust`:

- `:primary`: every domain it lists is blocked (subject to the precedence table).
- `:corroborating`: a domain it lists is blocked only once `config.corroboration_threshold` (default 2) **independent origins** list it.

"Independent" is the key word. Public blocklists copy each other: [`disposable/disposable`](https://github.com/disposable/disposable) declares that it imports mailchecker, fakefilter, wesbos and unkn0w, and groundcat imports disposable/disposable. Two copies of one mistake are one observation, so each source declares what it is `derived_from`, and a vote only counts when none of its upstreams that you also load carries the same domain.

Measured on 2026-10-17, that rule has teeth. With lineage declared, adding disposable/disposable, mailchecker and groundcat as corroborating sources to `RECOMMENDED` adds **zero** domains: everything they agree on is already explained by an upstream you load. Ignoring lineage instead would have "corroborated" 68,692 more, 64 of them in the [Tranco](https://tranco-list.eu) top 100k (`compaq.com`, `cafe24.com`, `24hourfitness.com`, `asana.biz`…). That is why `RECOMMENDED` is two primaries and nothing else.

The other measured sources ship as constants, so you can opt in knowingly:

| Constant | List | Licence | Trust | Notes |
|---|---|---|---|---|
| `DISPOSABLE_EMAIL_DOMAINS` | disposable-email-domains/disposable-email-domains | CC0 | primary | the default; also the bundled seed |
| `FAKEFILTER` | 7c/fakefilter | BSD-3 | primary | in `RECOMMENDED` |
| `DISPOSABLE` | disposable/disposable-email-domains | MIT | corroborating | ~97k domains, aggregates most others |
| `MAILCHECKER` | FGRibreau/mailchecker | MIT | corroborating | lists privacy relays |
| `GROUNDCAT` | groundcat/disposable-email-domain-list | MIT | corroborating | aggregator |
| `WESBOS` | wesbos/burner-email-providers | MIT | corroborating | no declared lineage, but 57% of it is also in mailchecker |

> [!WARNING]
> **About promoting `DISPOSABLE` to primary.** It is the broadest list, and the only one that carried `mail-burn.com` on 2026-10-17. On top of `RECOMMENDED` it adds 84,341 domains (70 of them in the Tranco top 100k, listed in `docs/evidence/2026-10-17-disposable-as-primary-tranco-top100k.csv`), and among them are real mail domains: China Unicom (`wo.com.cn`), the Japanese ISP ODN (`odn.ad.jp`), UQ mobile (`uqmobile.jp`), the Moscow ISP MTU (`mtu-net.ru`), plus `cafe24.com`, `24hourfitness.com`, `foxwoods.com` and more. The ones we verified are now in `never_disposable.txt`, but the rest of the list is unknown. If you still want it, `Nondisposable::Sources::DISPOSABLE.with(trust: :primary)` does it. For one specific burner domain, `config.additional_domains` is the precise tool.

Your own source is a Hash or a `Source`:

```ruby
config.sources = Nondisposable::Sources::RECOMMENDED + [
  { name: "ours", url: "https://example.com/burners.txt", trust: :corroborating, derived_from: %w[mailchecker] }
]
```

Sources must be `https`, plain text, one domain per line (`#` comments allowed). Names and URLs must be unique, and at least one source must be `:primary`.

### Privacy relays

Apple Hide My Email, DuckDuckGo, Firefox Relay, SimpleLogin/Proton Pass and addy.io forward to a real, long-lived inbox. They are not throwaways, but they do let one person hold many addresses. That is a policy decision, so it is a setting: `config.block_privacy_relays = false` (the default) **allows** them even when an upstream list carries them (mailchecker does), and `true` **refuses** them even when none does. The list is `data/privacy_relays.txt`; each domain covers its subdomains.

### Upgrading an existing install

Multi-source lists need one new table. The migration is additive, so you can deploy first and migrate later:

```bash
rails generate nondisposable:upgrade
rails db:migrate
```

Until the table exists (and again if you roll the migration back), the updater uses the default list exactly as before and logs a warning if you have configured other sources. During a rolling deploy an old process may still publish the single-source list once; the next update from a new process rebuilds the full one.

### How an update is published

Each source is fetched into its own row in `nondisposable_source_snapshots` (status, timestamp, sha256, count, the list itself). The stored list is then **rebuilt** from each source's last good snapshot, in one transaction, under a database advisory lock on PostgreSQL and MySQL (a process lock on SQLite, which already allows only one writer). Seeding takes the same lock. A new snapshot is refused, and the source's last good one kept, when:

- the download fails, takes longer than the source's `deadline` (30 s), or is larger than its `max_bytes` (8 MB, checked while streaming);
- more than 1% of its lines are not domain names (an HTML error page, a format change);
- it has fewer than `minimum_count` domains (1,000 for the presets);
- it is less than half the source's high-water mark, the largest size ever accepted for it (kept on its newest good snapshot, so neither pruning nor a series of 49% cuts can wear it down; `reset_baseline` is the human override), or more than three times its last good one;
- it is identical to a snapshot a human rolled back.

Every size is a count of *storable* domains (not junk, not a public suffix, not a known real provider, not a privacy relay), counted the same way whatever your settings, so a payload padded with such lines cannot pass for a full list and changing `block_privacy_relays` or `excluded_domains` never trips a guard. The list is never published empty. A primary that has never been fetched successfully blocks publishing, and the current table is kept as it is. The one exception is an EMPTY table, where the default source's bundled list stands in for it. So a first run can never replace a fresh seed with less than it, nor a table upgraded from 0.4/0.5 with an older bundled snapshot. Additions and removals are logged per source. A source that lists a known real provider, or a public suffix, is logged as a possible poisoning, and the entry is dropped. Accepting a snapshot, publishing and rolling back all happen under the same lock; downloads happen outside it.

> [!WARNING]
> **Two concurrency limits, by design:**
>
> - **SQLite: run the refresh from one process.** PostgreSQL and MySQL get a database-wide advisory lock; SQLite has none, so the lock is per process. Two *processes* refreshing at once can interleave (one can republish a merge it read before the other rolled a source back). Schedule `DisposableEmailDomainListUpdateJob` on a single job runner, and run `rollback` from that same process or when no update is running.
> - **Rolling deploys: quiesce the old updater.** Processes still running 0.5 or earlier replace the table without taking the lock, so their single-source list can overwrite a multi-source one, or leave back a row a new process just withdrew. When upgrading: pause the scheduled refresh job, deploy, run `rails g nondisposable:upgrade && rails db:migrate`, then resume it and run `Nondisposable::DomainListUpdater.update` once.

Two more tools:

```ruby
Nondisposable::DomainListUpdater.publish             # rebuild from snapshots, no download (after a config change)
Nondisposable::DomainListUpdater.rollback("fakefilter") # withdraw that source's newest snapshot (its payload stays refused) and republish
Nondisposable::DomainListUpdater.reset_baseline("fakefilter") # accept a genuine shrink: the guard now measures from today's size
```

## Updating the TLD list

The TLD snapshot is the deliberate opposite of the disposable list: it ships **inside the gem**, not in your database, and there is nothing for your app to schedule. Disposable domains number in the thousands and change every few days; TLDs are ~1,438 strings that change a handful of times a year, so a frozen `Set` costs one file read at boot, answers in O(1) with no query per signup, needs no migration, and can't be empty on a fresh install.

If ICANN delegates a TLD your installed version doesn't know about, don't wait for a release — that's what `config.additional_tlds` is for.

Maintainers refresh the snapshot from a checkout of this gem:

```bash
rake nondisposable:tlds:update   # rewrites data/iana_tlds.txt from data.iana.org
```

It refuses to overwrite a good list with an implausibly short one (a captive portal or a truncated body served with a `200`), writes to a temp file and moves it into place so an interrupted run can't leave half a root zone behind, and keeps IANA's own version header so you can always see which root zone you're shipping:

```ruby
Nondisposable::Tld.version # => "2026082301, Last Updated Mon Aug 24 07:07:01 2026 UTC"
```

The bundled Public Suffix List (`data/public_suffix_list.dat`, redistributed unmodified under the MPL 2.0) is refreshed the same way, with the same safeguards:

```bash
rake nondisposable:psl:update    # rewrites data/public_suffix_list.dat from publicsuffix.org
```

A stale PSL can only be less protective, never lock anyone out: a suffix created after the snapshot simply isn't known to be one.

## Troubleshooting

### SSL certificate verify failed (unable to get certificate CRL)

If you see this error when running `Nondisposable::DomainListUpdater.update`:

```
SSL_connect returned=1 errno=0 peeraddr=[::1]:10011 state=error: certificate verify failed (unable to get certificate CRL) (OpenSSL::SSL::SSLError)
```

This is **not** a bug in `nondisposable`. It's a known incompatibility between OpenSSL 3.6.0 and older versions of Ruby's `openssl` gem (3.3.0 and earlier).

The fix is to update the `openssl` gem to version 3.3.1 or later **in your Rails project**.

Add this to your Rails' project `Gemfile`:

```ruby
gem "openssl", "~> 3.3.2"
```

Then run:

```bash
bundle install
```

This issue is unlikely to occur in production, it's mostly a development-only issue. It's likely that the exact same codebase fails in development but works fine in production. It only occurs when you have OpenSSL 3.6.0 system-wide AND something intercepting HTTPS traffic (like Cursor's proxy). Users in production or using a regular terminal won't experience it.

This issue is more likely to occur if you're running your Rails console from within certain IDEs (like Cursor) that intercept HTTPS traffic through a local proxy. The updated `openssl` gem properly handles certificate verification in these environments.

For more details, see the [Ruby openssl gem issue](https://github.com/ruby/openssl/issues/949).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/nondisposable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
