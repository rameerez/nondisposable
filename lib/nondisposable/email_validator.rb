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
      #
      # HARD vs CONFIRMABLE — WHICH LOOKALIKES CAN BE WAVED THROUGH
      #
      # A lookalike error is only as strong as the evidence behind it:
      #
      #   - Invalid TLD (`gmail.con`, `gmailmcom`): HARD. No mail is delivered to
      #     a TLD that does not exist, so there is nothing to confirm.
      #   - Reviewed typo (data/known_typo_domains.txt, `gmial.com`): HARD. Someone
      #     checked; nobody has a mailbox there.
      #   - Any other lookalike (`gmail.co`, but also `ge.com` → me.com): a GUESS,
      #     so CONFIRMABLE. The error is added unless the record says the user
      #     confirmed the address as typed (Nondisposable::ConfirmableEmail). A
      #     real `ge.com` employee resubmits once and is never locked out.
      #
      # `true` and `:confirmable` mean the same thing. Before 0.5.0 `true` refused
      # every lookalike outright, which measured against the Tranco top 1M would
      # have refused staff at General Electric, EA and Aon (see CHANGELOG).
      def validate_each(record, attribute, value)
        return if value.blank?

        begin
          # Without an "@" the whole value is judged as a domain, as it always
          # has been — someone who typed only `tempmail.com` is still refused.
          # Unicode form: DisposableDomain canonicalises it, and needs the
          # unencoded spelling to match rows stored before 0.5.0.
          domain = value.to_s.include?('@') ? Nondisposable::Domain.from_email(value, unicode: true) : Nondisposable::Domain.unicode(value)
          return if domain.empty? # Invalid email format

          config = Nondisposable.configuration

          # A domain longer than DNS allows (RFC 1035; RFC 5321 caps it at
          # 255) cannot receive mail and is in no list, so "not disposable"
          # would be a lie: refuse it as invalid, whatever else is switched
          # on. Only for real addresses — a value without "@" is `format:`'s.
          if value.to_s.include?('@') && Nondisposable::Domain.too_long?(domain)
            return reject(record, attribute, config.invalid_tld_error_message)
          end

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
          impossible = tld.nil? || !Nondisposable::Tld.valid?(tld)
          invalid = config.check_tld && impossible
          blocked = config.check_tld && !invalid && Nondisposable::Tld.blocked?(tld)

          if invalid || config.reject_lookalike_domains
            suggestion = Nondisposable::Suggestion.for(value)
            # `@gmial.com` has no local part to build "Did you mean ..." from,
            # but it is still a reviewed typo: name the domain instead.
            if suggestion.nil? && config.lookalike_distance.to_i.positive?
              suggestion = Nondisposable::KnownTypos.correction_for(value)
            end
            if suggestion
              message = config.lookalike_error_message.sub('%{suggestion}', suggestion)
              # Hard: no confirmation can make an impossible TLD deliverable —
              # whether or not the host turned check_tld on, `gmail.con` cannot
              # receive the confirmation email — and a reviewed typo is not a
              # guess. The error stays a plain message, exactly as before 0.5.0.
              return reject(record, attribute, message) if impossible || Nondisposable::KnownTypos.include?(value)

              unless Nondisposable::ConfirmableEmail.confirmed?(record, attribute)
                # Typed, so a form can tell this error apart and offer the
                # "yes, this is right" checkbox: errors.of_kind?(:email, :lookalike_domain).
                record.errors.add(attribute, :lookalike_domain, message: message, suggestion: suggestion)
                return
              end
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
