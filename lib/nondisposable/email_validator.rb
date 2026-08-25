# frozen_string_literal: true

module ActiveModel
  module Validations
    class NondisposableValidator < EachValidator
      # Three independent questions about one address, in the order a human
      # would ask them, and AT MOST ONE error however many of them fire —
      # stacking "provider is not allowed" on top of "did you mean gmail.com?"
      # helps nobody:
      #
      #   1. Is this a throwaway provider?     (always on — the gem's whole job)
      #   2. Can we name the address they meant? (config.reject_lookalike_domains,
      #      or any invalid TLD we can correct — see below)
      #   3. Is the TLD real, and allowed?     (config.check_tld)
      #
      # WHY A NAMEABLE CORRECTION OUTRANKS THE GENERIC TLD ERROR
      #
      # `user@gmail.con` fails both 2 and 3. "Doesn't look like a real email
      # address" is true but useless; "Did you mean user@gmail.com?" is the same
      # verdict with the fix attached. So whenever we can name a correction we
      # use that message, whether the TLD was invalid or merely lookalike. The
      # rule is: a suggestion, if we have one, always phrases the rejection.
      def validate_each(record, attribute, value)
        return if value.blank?

        begin
          domain = value.to_s.split('@').last&.downcase
          return if domain.nil? # Invalid email format

          config = Nondisposable.configuration

          if Nondisposable::DisposableDomain.disposable?(domain)
            return reject(record, attribute, options[:message] || config.error_message)
          end

          return unless config.check_tld || config.reject_lookalike_domains
          # No "@" at all is a malformed value, and this validator has never
          # judged shape — that is what `format:` is for (see the README). Note
          # `example@gmailmcom` DOES have one: a domain missing its dot is a real
          # address at an impossible domain, which is very much our business.
          return unless value.to_s.include?('@')
          return unless Nondisposable::Tld.judgeable?(value)

          # nil here means the domain has NO TLD (`example@gmailmcom` — a
          # production-shaped typo that missed the dot), which fails "must end in a real TLD"
          # just as surely as `.con` does.
          tld = Nondisposable::Tld.extract(value)
          invalid = config.check_tld && (tld.nil? || !Nondisposable::Tld.valid?(tld))
          blocked = config.check_tld && !invalid && Nondisposable::Tld.blocked?(tld)

          if invalid || config.reject_lookalike_domains
            suggestion = Nondisposable::Suggestion.for(value)
            if suggestion
              return reject(record, attribute, config.lookalike_error_message.sub('%{suggestion}', suggestion))
            end
          end

          return reject(record, attribute, config.invalid_tld_error_message) if invalid
          return reject(record, attribute, config.blocked_tld_error_message) if blocked
        rescue StandardError => e
          if Nondisposable.configuration.on_check_failure == :reject
            Rails.logger.error "[nondisposable] Nondisposable validation error: #{e.message} — rejecting #{attribute} (on_check_failure = :reject)"
            record.errors.add(attribute, "is an invalid email address, cannot check if it's disposable")
          else
            Rails.logger.error "[nondisposable] Nondisposable validation error: #{e.message} — ALLOWING #{attribute} through without a disposable check (on_check_failure = :allow). Set config.on_check_failure = :reject to fail closed instead."
          end
        end
      end

      private

      def reject(record, attribute, message)
        record.errors.add(attribute, message)
        nil
      end
    end

    module HelperMethods
      # Kept for backwards compatibility
      def validates_nondisposable_email(*attr_names)
        validates_with NondisposableValidator, _merge_attributes(attr_names)
      end
    end
  end
end
