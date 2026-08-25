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

With `check_parent_domains` enabled (the default since 0.3.0), `user@x.tempmail.com` is blocked when `tempmail.com` is on the list. The check walks up to 3 parent labels (`a.b.c.tempmail.com` → `b.c.tempmail.com` → `c.tempmail.com` → `tempmail.com`) and never matches against bare TLDs like `com`. All candidates are checked in a single indexed query.

This is a deliberately minimal, dependency-free approximation of "registrable domain" matching: the gem doesn't ship a full [public suffix list](https://publicsuffix.org), so it can't tell that `co.uk` is a public suffix — which is harmless in practice, because public suffixes don't appear on the blocklist. If you need to allowlist a specific subdomain under a listed parent, add the exact subdomain to `excluded_domains`; an exact exclusion always wins. Excluding a parent domain also unblocks its subdomains.

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

Setting `reject_lookalike_domains = true` turns the same guess into a validation error naming the correction. Do that deliberately: a suggestion is a guess about intent, and a wrong guess stops a real person signing up with their real address. Two things keep that rare — matching stops at **one** edit by default (`lookalike_distance`), and an exact match against the bundled provider list always wins, which is why that list includes awkward pairs like `mail.com` (one insertion from `gmail.com`). Add anything we've missed with `config.additional_email_providers`; doing so both makes it a suggestion candidate and stops its users being told they mistyped.

The matching uses optimal string alignment distance rather than plain Levenshtein, so an adjacent swap counts as the one mistake a human actually made: `gmial.com` is distance 1, not 2.

#### How the two combine

At most one error is added, however many checks fire — and whenever the gem can name a correction, that phrasing wins:

| Address | `check_tld` only | with `reject_lookalike_domains` |
|---|---|---|
| `user@gmail.con` | "looks like a typo. Did you mean user@gmail.com?" | same |
| `user@zzz.con` | "doesn't look like a real email address" | same |
| `user@gmail.co` | accepted | "looks like a typo. Did you mean user@gmail.com?" |
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

## Updating disposable domains

To manually update the list of disposable domains, run:

```ruby
Nondisposable::DomainListUpdater.update
```

The fetch uses 10-second open/read timeouts and replaces the whole table atomically. If the remote fetch fails and your table is empty (e.g. a fresh install without network access), the updater automatically seeds from the blocklist snapshot bundled with the gem so you're never left unprotected; you can also trigger that explicitly with `Nondisposable::DomainListUpdater.seed` (it only seeds an empty table, and never overwrites existing data).

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
