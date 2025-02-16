# frozen_string_literal: true

require_relative "lib/nondisposable/version"

Gem::Specification.new do |spec|
  spec.name = "nondisposable"
  spec.version = Nondisposable::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Block disposable emails from signing up to your Rails app"
  spec.description = "Block disposable email addresses from signing up to your Rails app. Comes with a job so you can automatically update the database of disposable email domains on a regular basis (daily, weekly, etc)."
  spec.homepage = "https://github.com/rameerez/nondisposable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

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
end
