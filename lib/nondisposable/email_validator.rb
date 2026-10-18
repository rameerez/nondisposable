# frozen_string_literal: true

module ActiveModel
  module Validations
    class NondisposableValidator < EachValidator
      # Three independent questions about one address, and AT MOST ONE error
      # however many of them fire — stacking "provider is not allowed" on top
      # of "did you mean gmail.com?" helps nobody:
      #
      #   - Is this a throwaway provider?        (always on — the gem's whole job)
      #   - Can we name the address they meant?  (config.reject_lookalike_domains,
      #     or any invalid TLD we can correct — see below)
      #   - Is the TLD real, and allowed?        (config.check_tld)
      #
      # The answer is chosen in this order, first match wins:
      #
      #   1. A HARD correction: an impossible TLD or a reviewed typo we can name
      #      the fix for (`gmail.con`, `gmial.com`). "Did you mean …?"
      #   2. A throwaway provider. "provider is not allowed"
      #   3. A GUESS (`gnail.com`): the same "Did you mean …?", but confirmable.
      #   4. An invalid or blocked TLD.
      #
      # WHY A HARD CORRECTION OUTRANKS THE THROWAWAY CHECK (since 0.6.2)
      #
      # Upstream blocklists carry some of the very typos we reviewed: the
      # bundled snapshot lists `gmial.com`, `hotmai.com` and `hotmial.com`.
      # Both verdicts refuse the address, so the order only decides the
      # MESSAGE, and only one of them is true about the person typing: someone
      # at `ana@gmial.com` did not pick a temporary inbox, they missed a key
      # on the way to gmail.com. Being told their provider is a throwaway
      # sends them looking for a problem they don't have; "Did you mean
      # ana@gmail.com?" fixes it in one click. A hard correction is certain (no mail reaches
      # `.con`; somebody checked `gmial.com`), so it is safe to let it phrase a
      # refusal the blocklist would have made anyway. Until 0.6.2 the throwaway
      # check ran first, and these typos got the wrong message whenever the
      # table was loaded.
      #
      # It is answered BEFORE the blocklist is even asked, not just phrased
      # after it: a certain correction needs no database, so a lookup that
      # raises can neither wave `ana@gmial.com` through (on_check_failure =
      # :allow) nor bury the correction under the generic "cannot check"
      # error (:reject). And it is cheap — a hash lookup in the reviewed list,
      # and the ranker only for an ending that does not exist.
      #
      # A guess stays BEHIND the throwaway check. It is only a likelihood, and
      # the user can answer it: `gotmail.com` and `tmail.com` are both one
      # finger from a provider AND listed throwaways, so asking "did you mean
      # hotmail.com?" there would let them tick "yes, this is right" only to
      # be refused anyway on the next submit. A listed throwaway is the
      # stronger evidence, and the more useful answer. It is also the
      # expensive part (a distance walk over every provider), so it runs only
      # for addresses the blocklist did not already refuse: an ordinary
      # throwaway never pays for it.
      #
      # WHY A NAMEABLE CORRECTION OUTRANKS THE GENERIC TLD ERROR
      #
      # `user@gmail.con` fails both the lookalike and the TLD question. "Doesn't
      # look like a real email address" is true but useless; "Did you mean
      # user@gmail.com?" is the same verdict with the fix attached. So whenever
      # we can name a correction we use that message, whether the TLD was
      # invalid or merely lookalike. The rule is: a suggestion, if we have one,
      # always phrases the rejection — unless it is a guess about a domain we
      # KNOW is a throwaway (above).
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

          spelling = spelling_of(value, config)

          # 1. A certain correction: no database, no ranker for a real ending.
          # See "why a hard correction outranks the throwaway check" above. A
          # plain message, not the confirmable :lookalike_domain kind, so a
          # form never offers "yes, this is right" for it.
          return reject(record, attribute, config.lookalike_message(spelling.correction)) if spelling&.correction

          # 2. A throwaway provider.
          if Nondisposable::DisposableDomain.disposable?(domain)
            return reject(record, attribute, options[:message] || config.error_message)
          end

          return unless spelling

          # 3. A guess, which the user can confirm. Not when the ending is
          # impossible: spelling_of already asked the ranker then, and it had
          # nothing to name.
          if config.reject_lookalike_domains && !spelling.impossible
            suggestion = Nondisposable::Suggestion.for(value)
            if suggestion && !Nondisposable::ConfirmableEmail.confirmed?(record, attribute)
              # Typed, so a form can tell this error apart and offer the
              # "yes, this is right" checkbox: errors.of_kind?(:email, :lookalike_domain).
              record.errors.add(attribute, :lookalike_domain, message: config.lookalike_message(suggestion), suggestion: suggestion)
              return
            end
          end

          # 4. The TLD itself.
          return reject(record, attribute, config.invalid_tld_error_message) if spelling.invalid
          return reject(record, attribute, config.blocked_tld_error_message) if spelling.blocked
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

      # What the TLD and lookalike checks make of an address BEFORE anything
      # costly runs: no database, and no ranker unless the ending is
      # impossible.
      #
      #   correction  a CERTAIN correction (see #certain_correction), or nil
      #   impossible  the ending is not a TLD at all (`.con`, or no dot)
      #   invalid     the TLD fails check_tld
      #   blocked     the TLD is real, but blocked_tlds/allowed_tlds refuse it
      Spelling = Struct.new(:correction, :impossible, :invalid, :blocked, keyword_init: true)
      private_constant :Spelling

      # nil when neither check applies to this value at all.
      def spelling_of(value, config)
        return nil unless config.check_tld || config.reject_lookalike_domains
        # No "@" at all is a malformed value, and this validator has never
        # judged shape — that is what `format:` is for (see the README). Note
        # `example@gmailmcom` DOES have one: a domain missing its dot is a real
        # address at an impossible domain, which is very much our business.
        return nil unless value.to_s.include?('@')
        return nil unless Nondisposable::Tld.judgeable?(value)

        # nil here means the domain has NO TLD (`example@gmailmcom` — a
        # production-shaped typo that missed the dot), which fails "must end in a real TLD"
        # just as surely as `.con` does.
        tld = Nondisposable::Tld.extract(value)
        impossible = tld.nil? || !Nondisposable::Tld.valid?(tld)
        invalid = config.check_tld && impossible

        Spelling.new(
          correction: certain_correction(value, config, impossible),
          impossible: impossible,
          invalid: invalid,
          blocked: config.check_tld && !invalid && Nondisposable::Tld.blocked?(tld)
        )
      end

      # A correction no confirmation can override, or nil. Two kinds:
      #
      # - An impossible ending with anything the ranker can name (`gmail.con`):
      #   no mail reaches `.con`, so the guess about WHICH address they meant
      #   is the only uncertain part, and the refusal is not. Applies whether
      #   or not the host turned check_tld on — `gmail.con` cannot receive the
      #   confirmation email either way.
      # - A reviewed typo (`gmial.com`): somebody checked; nobody has a mailbox
      #   there. Only with reject_lookalike_domains on, and not at
      #   lookalike_distance 0, which switches the whole layer off.
      #
      # `@gmial.com` has no local part to build "Did you mean ..." from, but
      # it is still a reviewed typo: name the domain instead.
      def certain_correction(value, config, impossible)
        return nil unless config.lookalike_distance.to_i.positive?

        if impossible
          Nondisposable::Suggestion.for(value) || Nondisposable::KnownTypos.correction_for(value)
        elsif config.reject_lookalike_domains && Nondisposable::KnownTypos.include?(value)
          # Suggestion.for asks the reviewed list before the ranker, so this
          # never pays for a distance walk.
          Nondisposable::Suggestion.for(value) || Nondisposable::KnownTypos.correction_for(value)
        end
      end

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
