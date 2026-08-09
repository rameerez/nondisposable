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
end
```

#### Parent domain matching

With `check_parent_domains` enabled (the default since 0.3.0), `user@x.tempmail.com` is blocked when `tempmail.com` is on the list. The check walks up to 3 parent labels (`a.b.c.tempmail.com` → `b.c.tempmail.com` → `c.tempmail.com` → `tempmail.com`) and never matches against bare TLDs like `com`. All candidates are checked in a single indexed query.

This is a deliberately minimal, dependency-free approximation of "registrable domain" matching: the gem doesn't ship a full [public suffix list](https://publicsuffix.org), so it can't tell that `co.uk` is a public suffix — which is harmless in practice, because public suffixes don't appear on the blocklist. If you need to allowlist a specific subdomain under a listed parent, add the exact subdomain to `excluded_domains`; an exact exclusion always wins. Excluding a parent domain also unblocks its subdomains.

#### Failure mode

By default (`on_check_failure = :allow`), if the disposable check raises — say, the database is briefly unavailable — the signup goes through and an error is logged. This is availability-first: a broken check should not lock everyone out of signup. If you'd rather fail closed (reject signups whenever the check cannot run, as versions before 0.3.0 did), set `config.on_check_failure = :reject`.

### Direct Check

You can also check if an email is disposable directly:

```ruby
Nondisposable.disposable?('user@example.com') # => false
Nondisposable.disposable?('user@disposable-email.com') # => true
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
