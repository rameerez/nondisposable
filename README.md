# 🗑️ `nondisposable` - Block disposable email addresses in your Rails app

Nondisposable is a Ruby gem for Rails apps that checks and prevents users from signing up with disposable email addresses. It maintains a regularly updated database of known disposable email domains and provides ActiveRecord validations.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'nondisposable'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install nondisposable
```

After installing the gem, run the installation generator:

```
$ rails generate nondisposable:install
```

This will create the necessary migration file. Run the migration:

```
$ rails db:migrate
```

## Usage

To use Nondisposable in your models, add the following validation:

```ruby
class User < ApplicationRecord
  validates :email, nondisposable: true
end
```

You can customize the error message by creating an initializer:

```ruby
# config/initializers/nondisposable.rb
Nondisposable.configure do |config|
  config.error_message = "is not allowed. Please use a non-disposable email address."
end
```

To update the list of disposable domains, run:

```
$ rake nondisposable:update_disposable_domains
```

You can also use the provided whenever configuration to schedule daily updates. Add the following to your `config/schedule.rb`:

```ruby
every 1.day, at: '4:30 am' do
  rake "nondisposable:update_disposable_domains"
end
```

Then update your crontab:

```
$ whenever --update-crontab
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/nondisposable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
