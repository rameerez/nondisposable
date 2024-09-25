# frozen_string_literal: true

require_relative "lib/nondisposable/version"

Gem::Specification.new do |spec|
  spec.name = "nondisposable"
  spec.version = Nondisposable::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Prevent users from signing up with disposable email addresses in Rails applications."
  spec.description = "Nondisposable is a Ruby gem for Rails 7+ that checks and prevents users from signing up with disposable email addresses. It maintains a database of known disposable email domains and provides ActiveRecord validations."
  spec.homepage = "https://github.com/rameerez/nondisposable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rameerez/nondisposable"
  spec.metadata["changelog_uri"] = "https://github.com/rameerez/nondisposable/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0.0"
  spec.add_dependency "whenever", "~> 1.0"

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
