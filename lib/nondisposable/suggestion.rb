# frozen_string_literal: true

module Nondisposable
  # "Did you mean gmail.com?"
  #
  # A TLD check catches the typos that produce a domain ending which cannot
  # exist — `.con`, `.cpm`, `.ocm`. It structurally cannot catch the far more
  # common ones, because `.co` (Colombia), `.cm` (Cameroon) and `.om` (Oman) are
  # all real, delegated TLDs, as are `.se` and `.es`. `user@gmail.co` is a
  # perfectly well-formed address at a perfectly real TLD, and it is still
  # almost always a finger that slipped off the `m`.
  #
  # So this layer asks a different question: is this domain one keystroke away
  # from a well-known email provider, while not being one itself?
  #
  # HOW IT DECIDES
  #
  # Optimal string alignment distance (Damerau-Levenshtein restricted to
  # adjacent transpositions) against data/email_providers.txt. Transposition
  # matters more than it looks: `gmial.com` is the single most common Gmail
  # misspelling, and plain Levenshtein scores it 2 while a human sees one
  # mistake. Under OSA it scores 1, alongside `gmai.com`, `gmail.co` and
  # `gmail.con`.
  #
  # WHY THE DEFAULT THRESHOLD IS 1, AND WHY THIS IS OFF BY DEFAULT
  #
  # Every suggestion is a guess about intent, and a wrong guess wired to
  # `reject_lookalike_domains` stops a real person from signing up with their
  # real address. One edit is the distance at which a guess is safe enough to
  # act on; at two, legitimately distinct domains start colliding. The exact
  # match check runs first and always wins, which is why the provider list has
  # to be generous — see the header of data/email_providers.txt.
  #
  # Suggesting is always available and never blocks:
  #
  #   Nondisposable.suggestion_for("someone@gmial.com") # => "someone@gmail.com"
  #   Nondisposable.suggestion_for("someone@gmail.com") # => nil
  #
  # Blocking on it is a separate, deliberate opt-in
  # (`config.reject_lookalike_domains`), because "probably a typo" is a weaker
  # claim than "this TLD does not exist" and deserves a weaker remedy.
  module Suggestion
    LIST_PATH = File.expand_path('../../data/email_providers.txt', __dir__)

    class << self
      # The full corrected address, or nil when we have nothing useful to say.
      def for(email)
        email = email.to_s.strip
        local, _, domain = email.rpartition('@')
        return nil if local.empty? || domain.empty?

        corrected = correct_domain(domain.downcase)
        return nil if corrected.nil?

        "#{local}@#{corrected}"
      end

      # The corrected DOMAIN alone, or nil. Split out so a host can offer
      # "did you mean …?" next to a domain field, not just an email field.
      def correct_domain(domain)
        domain = domain.to_s.strip.downcase.delete_suffix('.')
        return nil if domain.empty?
        # A real provider is never a typo of another real provider.
        return nil if providers.include?(domain)

        threshold = Nondisposable.configuration.lookalike_distance.to_i
        return nil if threshold < 1

        best = nil
        best_distance = threshold + 1

        providers.each do |candidate|
          # Cheap rejection before the O(n*m) walk: an edit changes the length
          # by at most 1 per operation, so anything further apart than the
          # threshold in length alone cannot be within it.
          next if (candidate.length - domain.length).abs > threshold

          distance = osa_distance(domain, candidate, best_distance)
          next if distance >= best_distance

          best = candidate
          best_distance = distance
          break if distance == 1 # nothing can beat one edit; stop early
        end

        best
      end

      # Every domain we would suggest, as a frozen Set: the bundled list plus
      # anything the host added. Memoised per configuration object so a host
      # changing config in a test or console is picked up.
      def providers
        config = Nondisposable.configuration
        extra = Array(config.additional_email_providers).map { |d| d.to_s.strip.downcase }
        cache_key = extra.hash

        if @cache_key != cache_key || @providers.nil?
          @providers = (bundled_providers + extra).to_set.freeze
          @cache_key = cache_key
        end

        @providers
      end

      def reload!
        @providers = nil
        @bundled_providers = nil
        @cache_key = nil
        self
      end

      private

      def bundled_providers
        @bundled_providers ||= File.readlines(LIST_PATH, chomp: true).filter_map do |line|
          value = line.strip.downcase
          value unless value.empty? || value.start_with?('#')
        end
      end

      # Optimal string alignment distance, with an early bail-out.
      #
      # Two rows instead of a full matrix (we only ever need the previous two),
      # and if the best cell in a row already exceeds `cutoff` no later row can
      # come back under it — the distance only grows — so we stop. With ~250
      # candidates per lookup and a threshold of 1, almost every candidate exits
      # on the length check above or within the first row or two.
      # (Empty inputs need no special case: with an empty `a` the loop never
      # runs and the seeded row already holds the right answer, b.length.)
      def osa_distance(a, b, cutoff)
        prev_prev = nil
        prev = (0..b.length).to_a
        current = Array.new(b.length + 1)

        a.each_char.with_index do |a_char, i|
          current[0] = i + 1
          row_min = current[0]

          b.each_char.with_index do |b_char, j|
            cost = a_char == b_char ? 0 : 1
            value = [
              current[j] + 1,      # insertion
              prev[j + 1] + 1,     # deletion
              prev[j] + cost       # substitution
            ].min

            # Transposition: the one that makes `gmial` a single mistake.
            if i.positive? && j.positive? && a_char == b[j - 1] && a[i - 1] == b_char
              value = [value, prev_prev[j - 1] + cost].min
            end

            current[j + 1] = value
            row_min = value if value < row_min
          end

          return cutoff if row_min >= cutoff

          prev_prev = prev
          prev = current.dup
        end

        prev[b.length]
      end
    end
  end
end
