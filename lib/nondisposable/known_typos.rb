# frozen_string_literal: true

module Nondisposable
  # The only lookalike domains this gem refuses outright.
  #
  # "One edit from gmail.com" is a guess, and offline a guess cannot tell
  # `gmial.com` (a typo) from `ge.com` (General Electric, one edit from me.com).
  # So a guess may only ever produce a CONFIRMABLE error — the user can say
  # "yes, that is my address" and carry on. Refusing without that way out needs
  # something stronger than a guess: a domain somebody looked at and found to be
  # nothing but a misspelling of a provider — parked or for sale under the
  # provider's misspelled name, redirecting to the provider, or squatted by a
  # known typosquatter.
  #
  # Those reviewed domains live in data/known_typo_domains.txt, each with the
  # correction it is a typo OF. The evidence behind every entry is in
  # test/fixtures/lookalike_corpus.csv, and the test suite fails if an entry
  # loses it. Nothing generates this list automatically; see the file's header
  # for the bar an entry has to clear.
  #
  # Upstream blocklists list some of these too: the bundled snapshot has
  # `gmial.com`, `hotmai.com` and `hotmial.com`. That is left alone on purpose: both lists say "refuse it", and dropping the typos from
  # the stored list would let them through for every host that never switched
  # the lookalike layer on, and for every Nondisposable.disposable? caller.
  # What the overlap must not change is the MESSAGE, and the validator settles
  # that by asking this list before the throwaway check (see
  # NondisposableValidator), whatever the daily update brings in.
  module KnownTypos
    LIST_PATH = File.expand_path('../../data/known_typo_domains.txt', __dir__)

    class << self
      # Is this domain (or address) a reviewed typo?
      def include?(email_or_domain)
        !correction_for(email_or_domain).nil?
      end

      # The provider domain it is a typo of, or nil.
      def correction_for(email_or_domain)
        value = email_or_domain.to_s
        domain = value.include?('@') ? Domain.from_email(value) : Domain.normalize(value)
        return nil if domain.empty?
        # A host who added a provider has told us its users are real, which
        # outranks any review we did without knowing about them.
        return nil if host_providers.include?(domain)

        all[domain]
      end

      # typo => correction, frozen. Read once per process.
      def all
        @all ||= File.readlines(LIST_PATH, chomp: true).each_with_object({}) do |line, map|
          value = line.sub(/#.*/, '').strip
          next if value.empty?

          typo, correction = value.split(/\s+/, 2)
          map[Domain.normalize(typo)] = Domain.normalize(correction)
        end.freeze
      end

      def reload!
        @all = nil
        self
      end

      private

      def host_providers
        Array(Nondisposable.configuration.additional_email_providers).map { |d| Domain.normalize(d) }
      end
    end
  end
end
