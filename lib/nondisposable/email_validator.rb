# frozen_string_literal: true

module Nondisposable
  # A validation error whose message was resolved when it was added, and is
  # never resolved again.
  #
  # An ordinary `errors.add(:email, :some_type, message: "…")` keeps the type
  # and looks the message up AGAIN every time it is read: the first key of
  # ActiveModel's chain in whatever locale is current then, and I18n
  # interpolation over the text. For "Did you mean …?" both are hazards. The
  # text contains what the user typed, and `%`, `{` and `}` are legal in a
  # local part, so `a%{x}b@gnail.com` made errors.full_messages raise
  # I18n::MissingInterpolationArgument (since 0.5.0) and `a%{value}b@…` pasted
  # the whole address into the middle of it. And a Symbol message we already
  # checked could resolve differently at render time (another locale, a
  # translation Proc that raises the second time), outside any fallback.
  #
  # So the message is frozen here, while the type and details stay what a
  # form and an API expect: `errors.of_kind?(:email, :lookalike_domain)`,
  # `errors.details[:email]` => [{ error: :lookalike_domain, suggestion: … }].
  # It is in the locale of the request that validated, which is the request
  # that renders it.
  class LookalikeError < ActiveModel::Error
    def initialize(base, attribute, type, resolved_message, **options)
      super(base, attribute, type, **options)
      @resolved_message = resolved_message
    end

    def message
      @resolved_message
    end
  end
end

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
          return add_lookalike_error(record, attribute, config, spelling.correction, confirmable: false) if spelling&.correction

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
              return add_lookalike_error(record, attribute, config, suggestion, confirmable: true)
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

      # The "Did you mean …?" error, hard or confirmable.
      #
      # The confirmable one is always typed :lookalike_domain (with the
      # suggestion in its details), so a form can tell it apart and offer the
      # "yes, this is right" checkbox: errors.of_kind?(:email, :lookalike_domain).
      # The hard one is a plain message, exactly as before 0.5.0 — or, for a
      # Symbol, an error of that name, just as error_message and the TLD
      # messages are added.
      #
      # A Symbol resolves through the same ActiveModel chain as every other
      # Rails error name, and the confirmable error still honours a per-model
      # `lookalike_domain` translation (#confirmable_message) — but NOW, once,
      # into a String (see Nondisposable::LookalikeError for why it is never
      # resolved again). A
      # translation that is missing, names a variable we don't pass, or is a
      # whole group (a Hash) is a refusal with a broken message, and we refuse
      # with the default message instead — never a raise, which
      # on_check_failure = :allow would turn into an acceptance.
      def add_lookalike_error(record, attribute, config, suggestion, confirmable:)
        key = config.lookalike_error_message

        if confirmable
          add_resolved(record, attribute, :lookalike_domain, confirmable_message(record, attribute, config, suggestion), suggestion)
        elsif key.is_a?(Symbol)
          message = resolve_rails_message(record, attribute, config, key, suggestion) || config.default_lookalike_message(suggestion)
          add_resolved(record, attribute, key, message, suggestion)
        else
          # A plain String error, as since 0.5.0: no translation lookup, and
          # never interpolated when read, so nothing to freeze.
          record.errors.add(attribute, config.lookalike_message(suggestion))
        end
        nil
      end

      # The confirmable error's text, computed exactly as ActiveModel used to
      # compute it on every read of `errors.add(attr, :lookalike_domain,
      # message: …)`, but once:
      #
      # - A Symbol replaces the type in Rails' lookup, so it is its own
      #   chain (#resolve_rails_message).
      # - Anything else is the default for the FIRST key of the chain,
      #   activemodel/activerecord.errors.models.<model>.attributes.<attr>.lookalike_domain,
      #   so an app that translated that key keeps its translation (it did
      #   until 0.6.1, and must not lose it on upgrade). A String goes in as
      #   the template it is, with %{suggestion} as a VALUE: I18n never
      #   rescans a value, so a `%{x}` the user typed is printed, not
      #   interpolated. A callable's (or a #sub object's) output is already
      #   final, so its `%` are escaped for the same reason.
      def confirmable_message(record, attribute, config, suggestion)
        key = config.lookalike_error_message
        if key.is_a?(Symbol)
          return resolve_rails_message(record, attribute, config, key, suggestion) || config.default_lookalike_message(suggestion)
        end

        template = key.is_a?(String) ? key : config.lookalike_message(suggestion).gsub('%', '%%')
        text = record.errors.generate_message(attribute, :lookalike_domain, message: template, suggestion: suggestion)
        raise TypeError, "it resolved to #{text.class}, not a String" unless text.is_a?(String)

        text
      rescue StandardError => e
        config.default_lookalike_message(suggestion, e) # logs it
      end

      # Errors#add would build an ActiveModel::Error that re-resolves its
      # message on every read; this appends one that does not, the same way
      # Errors#add appends its own.
      def add_resolved(record, attribute, type, message, suggestion)
        record.errors.objects.append(
          Nondisposable::LookalikeError.new(record, attribute.to_sym, type, message, suggestion: suggestion)
        )
      end

      # This Rails error name as a String for this record, in the current
      # locale (and its I18n fallbacks, when the host has them on), or nil
      # when it cannot be one.
      def resolve_rails_message(record, attribute, config, key, suggestion)
        text = record.errors.generate_message(attribute, key, suggestion: suggestion, raise: true)
        raise TypeError, "it resolved to #{text.class}, not a String" unless text.is_a?(String)

        text
      rescue StandardError => e
        config.default_lookalike_message(suggestion, e) # logs it
        nil
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
