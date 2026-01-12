# frozen_string_literal: true

require_relative "nondisposable/version"
require_relative "nondisposable/engine"
require_relative "nondisposable/email_validator"
require_relative "nondisposable/domain_list_updater"

module Nondisposable
  class Error < StandardError; end

  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  def self.disposable?(email)
    return false if email.nil? || !email.include?('@')
    domain = email.to_s.split('@').last.downcase
    DisposableDomain.disposable?(domain)
  end

  class Configuration
    attr_accessor :error_message, :additional_domains, :excluded_domains

    def initialize
      @error_message = "provider is not allowed"
      @additional_domains = []
      @excluded_domains = []
    end
  end
end
