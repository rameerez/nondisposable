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

Finally, populate the initial list of disposable domains:

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
end
```

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
