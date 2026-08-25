# frozen_string_literal: true

require_relative "nondisposable/version"
require_relative "nondisposable/engine"
require_relative "nondisposable/tld"
require_relative "nondisposable/suggestion"
require_relative "nondisposable/email_validator"
require_relative "nondisposable/domain_list_updater"
require_relative "nondisposable/tld_list_updater"

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

  # Does this address end in a TLD that actually exists?
  #
  # A different question from #disposable?, catching a different kind of bad
  # address: `user@gmail.con` is not a throwaway, it is a typo that produces an
  # account nobody can ever reach. Answers true for anything we cannot judge —
  # no domain, no dot, an IP literal — so it is safe to call on any input; pair
  # it with a format validation if you also care about shape.
  def self.valid_tld?(email)
    return true unless Tld.judgeable?(email)

    tld = Tld.extract(email)
    return false if tld.nil? # A domain with no TLD can't end in a real one

    Tld.valid?(tld) && !Tld.blocked?(tld)
  end

  # "someone@gmial.com" => "someone@gmail.com", or nil when we have nothing
  # useful to say. Never blocks anything by itself — hand it to a user and let
  # them decide. See Nondisposable::Suggestion for how it decides.
  def self.suggestion_for(email)
    Suggestion.for(email)
  end

  class Configuration
    ON_CHECK_FAILURE_MODES = [:allow, :reject].freeze

    attr_accessor :error_message, :additional_domains, :excluded_domains
    # Whether to also match parent domains: with the default true, an email at
    # x.tempmail.com is blocked when tempmail.com is on the list (checks up to
    # DisposableDomain::PARENT_MATCH_DEPTH parent labels, never a bare TLD).
    attr_accessor :check_parent_domains
    attr_reader :on_check_failure

    # ---- TLD validity (Nondisposable::Tld) ----------------------------------

    # OFF by default, and it stays off: upgrading a gem must never silently
    # start rejecting addresses that were fine yesterday. Turn it on to reject
    # addresses whose TLD is not in the IANA root zone — `user@gmail.con` and
    # friends, which are typos rather than throwaways but produce an account
    # nobody can ever reach.
    attr_accessor :check_tld

    # Your escape hatch from a stale snapshot. A TLD delegated after this gem's
    # release is unknown to the bundled list; naming it here accepts it
    # immediately, with no release to wait for. Dots optional: "app" == ".app".
    attr_accessor :additional_tlds

    # TLDs to refuse even though they are perfectly real. The usual reason is
    # abuse economics rather than validity — the historically free Freenom set
    # (%w[tk ml ga cf gq]) is the classic example.
    attr_accessor :blocked_tlds

    # Allowlist mode: when set, ONLY these TLDs are accepted and every other one
    # is refused. nil (the default) means "any TLD in the root zone". ⚠️ This is
    # a blunt instrument — `%w[es]` turns away every customer who happens to use
    # a .com address. Reach for blocked_tlds first.
    attr_accessor :allowed_tlds

    # ---- Lookalike domains (Nondisposable::Suggestion) ----------------------

    # Reject addresses one edit away from a well-known provider — `gmail.co`,
    # `gmial.com`, `hotmial.com` — with a message naming the correction.
    #
    # OFF by default and worth leaving off unless you have thought about it: a
    # suggestion is a guess about intent, and a wrong guess here stops a real
    # person signing up with their real address. `Nondisposable.suggestion_for`
    # is always available and blocks nothing, which is the gentler way to use
    # this: show the hint, let the human decide.
    attr_accessor :reject_lookalike_domains

    # How many edits still count as "a typo". 1 (the default) is the distance at
    # which acting on a guess is safe; at 2, genuinely different domains start
    # colliding with each other. 0 disables suggestions entirely.
    attr_accessor :lookalike_distance

    # Providers to add to the bundled list — your own domain, a regional
    # provider we missed. Adding one both makes it a suggestion candidate and,
    # more importantly, stops its users being told they made a typo.
    attr_accessor :additional_email_providers

    # ---- Error messages -----------------------------------------------------

    attr_accessor :invalid_tld_error_message, :blocked_tld_error_message
    # %{suggestion} is replaced with the full corrected address.
    attr_accessor :lookalike_error_message

    def initialize
      @error_message = "provider is not allowed"
      @additional_domains = []
      @excluded_domains = []
      @on_check_failure = :allow
      @check_parent_domains = true

      @check_tld = false
      @additional_tlds = []
      @blocked_tlds = []
      @allowed_tlds = nil

      @reject_lookalike_domains = false
      @lookalike_distance = 1
      @additional_email_providers = []

      @invalid_tld_error_message = "doesn't look like a real email address"
      @blocked_tld_error_message = "domain ending is not allowed"
      @lookalike_error_message = "looks like a typo. Did you mean %{suggestion}?"
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
