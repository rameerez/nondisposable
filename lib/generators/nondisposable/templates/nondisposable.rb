Nondisposable.configure do |config|
  # Customize the error message if needed
  # config.error_message = "is not allowed. Please use a non-disposable email address."
  #
  # Add custom domains you want to be considered as disposable
  # config.additional_domains = ['custom-disposable-domain.com']
  #
  # Exclude domains that are considered disposable but you want to allow anyways
  # config.excluded_domains = ['false-positive-domain.com']
  #
  # What to do when the disposable check itself fails (e.g. database hiccup):
  #   :allow  - let the signup through and log an error (availability-first, default)
  #   :reject - block the signup with a validation error (fail closed)
  # config.on_check_failure = :allow
  #
  # Also match parent domains: an email at x.tempmail.com is blocked when
  # tempmail.com is on the list (checks every parent down to the registrable domain). Default: true
  # config.check_parent_domains = true

  # ---- Where the blocklist comes from ----
  #
  # Default: the single disposable-email-domains list this gem has always used.
  # RECOMMENDED adds fakefilter, a second list that watches temp-mail sites
  # directly (+3,275 domains on 2026-10-17, no known real provider among them).
  # config.sources = Nondisposable::Sources::RECOMMENDED
  #
  # :corroborating sources only block a domain once this many INDEPENDENT
  # lists carry it (a list that copies another doesn't count twice).
  # config.corroboration_threshold = 2
  #
  # Privacy relays (Hide My Email, DuckDuckGo, Firefox Relay, SimpleLogin,
  # addy.io) forward to a real inbox. Allowed by default, even when an upstream
  # list carries them; set to true to refuse them.
  # config.block_privacy_relays = false
  #
  # Who wins when lists disagree (top wins): excluded_domains, the gem's
  # never-disposable list of real providers, additional_domains, the
  # privacy-relay setting, the upstream sources.

  # ---- Catching typos ----
  #
  # A disposable address is someone hiding from you. A typo is someone who
  # wanted to reach you and won't be able to: user@gmail.con is a real person
  # whose account nobody can ever reach, because .con does not exist.
  # Both checks below are OFF by default.

  # Reject addresses whose TLD isn't in the IANA root zone (gmail.con,
  # outlook.ed, and domains with no dot at all like example@gmailmcom).
  # config.check_tld = true
  #
  # Accept a TLD delegated after your installed gem version shipped — so a
  # stale snapshot can never leave a real customer stuck.
  # config.additional_tlds = ['newtld']
  #
  # Refuse TLDs that are real but unwelcome (the historically free Freenom set):
  # config.blocked_tlds = %w[tk ml ga cf gq]
  #
  # Or invert it into an allowlist. Careful: %w[es] turns away every .com
  # customer you have.
  # config.allowed_tlds = nil

  # Flag addresses one keystroke from a well-known provider (gmail.co,
  # gmial.com). A TLD check CANNOT catch these — .co, .cm and .om are Colombia,
  # Cameroon and Oman, all real.
  #
  # Reviewed typos (data/known_typo_domains.txt) are refused outright. Every
  # other lookalike is a guess — ge.com is one edit from me.com and is General
  # Electric — so it is a CONFIRMABLE error: the user ticks "yes, this is my
  # address" and passes. Wire that checkbox first (see
  # Nondisposable::ConfirmableEmail in the README), or a real user at a
  # lookalike domain has no way through. `true` means the same as :confirmable.
  # config.reject_lookalike_domains = :confirmable
  #
  # How many edits still count as a typo. 1 is safe; 2 starts colliding with
  # genuinely different domains. 0 disables suggestions entirely.
  # config.lookalike_distance = 1
  #
  # Providers we missed, or your own domain. Adding one both makes it a
  # suggestion candidate AND stops its users being told they made a typo.
  # config.additional_email_providers = ['yourcompany.com']

  # config.invalid_tld_error_message = "doesn't look like a real email address"
  # config.blocked_tld_error_message = "domain ending is not allowed"
  # config.lookalike_error_message = "looks like a typo. Did you mean %{suggestion}?"
  # ...or a Rails error name, like the messages above: looked up per request
  # through ActiveModel's chain, e.g. errors.messages.email_lookalike in your
  # locale files, with %{suggestion} to interpolate:
  # config.lookalike_error_message = :email_lookalike
end
