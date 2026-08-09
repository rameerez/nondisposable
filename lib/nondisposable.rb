# frozen_string_literal: true

require_relative "nondisposable/version"
require_relative "nondisposable/engine"
require_relative "nondisposable/email_validator"
require_relative "nondisposable/domain_list_updater"

module Nondisposable
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    # Lazily initialized so the gem works safely even when the host app never
    # runs an initializer (previously a nil configuration made every check
    # raise, which the validator surfaced as a validation error on all emails).
    def configuration
      @configuration ||= Configuration.new
    end
  end

  def self.configure
    yield(configuration)
  end

  def self.disposable?(email)
    return false if email.nil? || !email.include?('@')
    domain = email.to_s.split('@').last
    return false if domain.nil? || domain.empty?
    DisposableDomain.disposable?(domain.downcase)
  end

  class Configuration
    ON_CHECK_FAILURE_MODES = [:allow, :reject].freeze

    attr_accessor :error_message, :additional_domains, :excluded_domains
    attr_reader :on_check_failure

    def initialize
      @error_message = "provider is not allowed"
      @additional_domains = []
      @excluded_domains = []
      @on_check_failure = :allow
    end

    # What the validator does when the disposable check itself raises
    # (e.g. the database is unavailable):
    #   :allow  - let the record through and log an error (availability-first, default)
    #   :reject - add a validation error, blocking the record (fail closed)
    def on_check_failure=(mode)
      mode = mode.to_sym if mode.respond_to?(:to_sym)
      unless ON_CHECK_FAILURE_MODES.include?(mode)
        raise ArgumentError, "on_check_failure must be one of #{ON_CHECK_FAILURE_MODES.map(&:inspect).join(', ')} (got #{mode.inspect})"
      end

      @on_check_failure = mode
    end
  end
end
