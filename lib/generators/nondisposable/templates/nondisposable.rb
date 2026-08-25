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
  # tempmail.com is on the list (checks up to 3 parent labels). Default: true
  # config.check_parent_domains = true

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

  # Reject addresses one keystroke from a well-known provider (gmail.co,
  # gmial.com). A TLD check CANNOT catch these — .co, .cm and .om are Colombia,
  # Cameroon and Oman, all real.
  #
  # Think before switching this on: a suggestion is a guess about intent, and a
  # wrong guess stops a real person signing up with their real address.
  # Nondisposable.suggestion_for(email) is always available and blocks nothing,
  # which is the gentler way to use this — show the hint, let the human decide.
  # config.reject_lookalike_domains = true
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
end
