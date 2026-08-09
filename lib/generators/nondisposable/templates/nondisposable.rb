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
end
