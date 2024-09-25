# frozen_string_literal: true

module Nondisposable
  class Engine < ::Rails::Engine
    isolate_namespace Nondisposable

    initializer "nondisposable.assets.precompile" do |app|
      app.config.assets.precompile += %w( nondisposable/application.css nondisposable/application.js )
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end
  end
end
