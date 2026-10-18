# frozen_string_literal: true

require_relative "nondisposable/version"
require_relative "nondisposable/engine"
require_relative "nondisposable/domain"
require_relative "nondisposable/public_suffix"
require_relative "nondisposable/precedence"
require_relative "nondisposable/source"
require_relative "nondisposable/source_merge"
require_relative "nondisposable/source_fetcher"
require_relative "nondisposable/tld"
require_relative "nondisposable/known_typos"
require_relative "nondisposable/suggestion"
require_relative "nondisposable/confirmable_email"
require_relative "nondisposable/email_validator"
require_relative "nondisposable/domain_list_updater"
require_relative "nondisposable/tld_list_updater"
require_relative "nondisposable/public_suffix_list_updater"

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
    return false if email.nil? || !email.to_s.include?('@')
    # Unicode form: DisposableDomain canonicalises it itself, and needs the
    # unencoded spelling to match rows stored before 0.5.0.
    domain = Domain.from_email(email, unicode: true)
    return false if domain.empty?
    DisposableDomain.disposable?(domain)
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
    LOOKALIKE_MODES = [false, true, :confirmable].freeze
    DEFAULT_LOOKALIKE_ERROR_MESSAGE = "looks like a typo. Did you mean %{suggestion}?"

    attr_accessor :error_message, :additional_domains, :excluded_domains
    # Whether to also match parent domains: with the default true, an email at
    # x.tempmail.com is blocked when tempmail.com is on the list (checks
    # every parent down to the registrable domain, never a public suffix).
    attr_accessor :check_parent_domains
    attr_reader :on_check_failure

    # ---- Blocklist sources (Nondisposable::Source) --------------------------

    # Where the list of disposable domains comes from: an ordered list of
    # Nondisposable::Source objects (or Hashes of their attributes). The
    # default is the single list this gem has always used, so upgrading changes
    # nothing. Nondisposable::Sources::RECOMMENDED adds a second, independent
    # primary. Needs the nondisposable_source_snapshots table
    # (`rails g nondisposable:upgrade`); without it only the default is used.
    attr_accessor :sources

    # How many independent ORIGINS must list a domain before a :corroborating
    # source's entry is blocked. Copies don't count: see Nondisposable::Source.
    attr_accessor :corroboration_threshold

    # Privacy relays (Apple Hide My Email, DuckDuckGo, Firefox Relay,
    # SimpleLogin, addy.io — data/privacy_relays.txt) forward to a real,
    # long-lived inbox. false (the default) ALLOWS them even when an upstream
    # list carries them; true REFUSES them even when none does.
    attr_accessor :block_privacy_relays

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

    # Flag addresses one edit away from a well-known provider — `gmail.co`,
    # `gmial.com`, `hotmial.com` — with a message naming the correction.
    #
    #   false        (default) never flag; Nondisposable.suggestion_for still works
    #   :confirmable flag them. Reviewed typos (data/known_typo_domains.txt) are
    #                refused outright; every other lookalike is a guess, and the
    #                user can confirm the address as typed and pass — see
    #                Nondisposable::ConfirmableEmail.
    #   true         the same as :confirmable. Before 0.5.0 it refused every
    #                lookalike, including real organisations' domains (ge.com,
    #                bol.com, one.com…) one edit from a provider.
    #
    # Worth leaving off unless your form can show the confirmation: without it a
    # user at a domain that merely looks like a typo has no way through.
    attr_reader :reject_lookalike_domains

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

    # "Did you mean …?", in one of three forms (see #lookalike_message):
    #
    #   "looks like a typo. Did you mean %{suggestion}?"   a String (default)
    #   :"errors.messages.email_typo"                      an I18n key
    #   ->(suggestion) { "…#{suggestion}…" }               a callable
    #
    # %{suggestion} is the full corrected address (or the corrected domain,
    # for a value with nothing before the "@").
    attr_accessor :lookalike_error_message

    def initialize
      @error_message = "provider is not allowed"
      @additional_domains = []
      @excluded_domains = []
      @on_check_failure = :allow
      @check_parent_domains = true

      @sources = Nondisposable::Sources::DEFAULT
      @corroboration_threshold = 2
      @block_privacy_relays = false

      @check_tld = false
      @additional_tlds = []
      @blocked_tlds = []
      @allowed_tlds = nil

      @reject_lookalike_domains = false
      @lookalike_distance = 1
      @additional_email_providers = []

      @invalid_tld_error_message = "doesn't look like a real email address"
      @blocked_tld_error_message = "domain ending is not allowed"
      @lookalike_error_message = DEFAULT_LOOKALIKE_ERROR_MESSAGE
    end

    # The lookalike error for this suggestion, resolved NOW, at validation
    # time, so a Symbol or a callable answers in the locale of the request
    # being validated rather than whichever locale the initializer ran in.
    #
    # - A Symbol is an I18n key, looked up with `suggestion:` to interpolate.
    #   A missing translation falls back to the default English message
    #   rather than printing "Translation missing" to a user.
    # - Anything that responds to #call is called with the suggestion.
    # - Anything else is treated as before 0.6.2: `%{suggestion}` replaced
    #   with #sub. That keeps a String exactly as it was, and keeps working
    #   any object a host passed that answers #sub (the only way to localise
    #   this message until now).
    #
    # NEVER RAISES. By the time we phrase this message the address is already
    # refused; the only open question is the wording. A translation naming a
    # variable we don't pass (`%{address}`), a translation Proc or a callable
    # that raises would otherwise reach the validator's rescue, where the
    # default on_check_failure = :allow ACCEPTS the address — a listed typo
    # let through by a broken locale file. So any failure falls back to the
    # default English message, logged so the host can fix it.
    def lookalike_message(suggestion)
      message = lookalike_error_message
      return I18n.t(message, suggestion: suggestion, default: DEFAULT_LOOKALIKE_ERROR_MESSAGE) if message.is_a?(Symbol)
      return message.call(suggestion).to_s if message.respond_to?(:call)

      message.sub('%{suggestion}', suggestion)
    rescue StandardError => e
      log_message = "[nondisposable] Could not build lookalike_error_message (#{e.class}: #{e.message}); using the default message, the address is still refused."
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error(log_message)
      else
        warn log_message
      end
      DEFAULT_LOOKALIKE_ERROR_MESSAGE.sub('%{suggestion}', suggestion.to_s)
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

    # Strings are accepted for config loaded from YAML/ENV ("confirmable",
    # "true"); anything else raises, so a typo in an initializer fails at boot
    # instead of silently meaning "on".
    def reject_lookalike_domains=(mode)
      mode = false if mode.nil?
      mode = { 'true' => true, 'false' => false }.fetch(mode, mode.to_sym) if mode.is_a?(String)
      unless LOOKALIKE_MODES.include?(mode)
        raise ArgumentError, "reject_lookalike_domains must be one of #{LOOKALIKE_MODES.map(&:inspect).join(', ')} (got #{mode.inspect})"
      end

      @reject_lookalike_domains = mode
    end
  end
end
