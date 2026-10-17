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
  # WHAT ONE EDIT CANNOT TELL APART, AND THE TWO FILTERS THAT FOLLOW
  #
  # Replaying "one edit from a provider" against the Tranco top 1M (2026-10-17,
  # docs/evidence/) flagged 707 domains, and a lot of them are large real
  # organisations: ge.com, mi.com and se.com are one edit from me.com; ea.com and
  # aa.com from ya.com; bol.com and uol.com from aol.com; grail.com from
  # gmail.com. Distance alone cannot see the difference, so two filters decide
  # what is worth suggesting at all:
  #
  #   1. SHORT NAMES ONLY TAKE EDITS AFTER THE NAME. When a provider's name is
  #      four characters or fewer (me, ya, qq, aol, msn, mail, live, zoho…),
  #      one edit inside the name lands on somebody else's real domain far more
  #      often than on a typo. `me.cmo` and `live.cm` are still suggested;
  #      `ge.com`, `mil.ru` and `love.com` are not.
  #   2. EVERY EDIT MUST LOOK LIKE A FINGER. A swap (`gmial`), a dropped letter
  #      (`gmal`, `gmail.co`), a doubled letter (`gmmail`), an extra vowel
  #      (`gamail`) or a neighbouring key on QWERTY (`gnail`, `gmail.con`) is
  #      how people mistype. A letter from across the keyboard (`grail`,
  #      `pmail`, `hive`) is how people spell a different word, and the same
  #      holds after the name: `.au` is not a slip for `.ar`, nor `.dev` for
  #      `.de`. Dropping the FIRST letter is not counted either — `cloud.com`
  #      and `aver.com` are what that spells.
  #
  # Measured on the 70% tuning split of test/fixtures/lookalike_corpus.csv
  # (precision over typo+real rows): distance alone 0.08, filter 1 alone 0.30,
  # both 0.58, at 78% recall of reviewed typos. The corpus is the Tranco top 1M,
  # so it is crowded with real popular domains — a signup form sees far more
  # typos per lookalike than this does. The untouched 30% holdout is measured
  # by test/nondisposable/lookalike_corpus_test.rb.
  #
  # These filters only decide what to SUGGEST. They are a likelihood, not proof,
  # and nothing in this file ever justifies refusing an address on its own —
  # see Nondisposable::KnownTypos for the only domains the gem refuses outright,
  # and ActiveModel::Validations::NondisposableValidator for how a suggestion
  # becomes a confirmable error rather than a wall.
  #
  # WHY THE DEFAULT THRESHOLD IS 1, AND WHY THIS IS OFF BY DEFAULT
  #
  # One edit is the distance at which a guess is worth showing; at two,
  # legitimately distinct domains start colliding. The exact match check runs
  # first and always wins, which is why the provider list has to be generous —
  # see the header of data/email_providers.txt.
  #
  # Suggesting is always available and never blocks:
  #
  #   Nondisposable.suggestion_for("someone@gmial.com") # => "someone@gmail.com"
  #   Nondisposable.suggestion_for("someone@gmail.com") # => nil
  module Suggestion
    LIST_PATH = File.expand_path('../../data/email_providers.txt', __dir__)

    # A provider name this short only takes edits after the name. See filter 1
    # in the header for the evidence.
    SHORT_NAME_LENGTH = 4

    VOWELS = 'aeiou'

    # Physical neighbours on a QWERTY keyboard, the layout of Spain, Latin
    # America and the English-speaking world (and the default on phones there).
    # `ñ` sits right of `l` on the Spanish layout. AZERTY and QWERTZ are left out
    # on purpose: unioning them makes every key a neighbour of more keys, and
    # QWERTZ's z/y swap alone would start suggesting zoho.com to zozo.com.
    KEYBOARD_ROWS = %w[1234567890 qwertyuiop asdfghjklñ zxcvbnm].freeze

    class << self
      # The full corrected address, or nil when we have nothing useful to say.
      def for(email)
        email = email.to_s.strip
        local, _, domain = email.rpartition('@')
        return nil if local.empty? || domain.empty?

        corrected = correct_domain(domain)
        return nil if corrected.nil?

        "#{local}@#{corrected}"
      end

      # The corrected DOMAIN alone, or nil. Split out so a host can offer
      # "did you mean …?" next to a domain field, not just an email field.
      def correct_domain(domain)
        typed = Domain.unicode(domain)
        return nil if typed.empty?
        # A real provider is never a typo of another real provider.
        return nil if providers.include?(Domain.normalize(typed))
        # 0 switches the whole layer off, reviewed list included.
        return nil if Nondisposable.configuration.lookalike_distance.to_i < 1

        # A reviewed typo carries its own correction, and it wins over any
        # guess: the list exists precisely because we checked it.
        KnownTypos.correction_for(typed) || guess(typed)
      end

      # The ranker alone: distance plus the two filters, without the reviewed
      # list. Public so the corpus test can measure the guess on its own —
      # measuring it with the list in front would mostly measure the list.
      def guess(domain)
        typed = Domain.unicode(domain)
        return nil if typed.empty?
        return nil if providers.include?(Domain.normalize(typed))

        # Punycode letters are an encoding, not keystrokes: `xn--gmal-xpa.com`
        # is somebody typing `gmaíl.com`, and its distance to gmail.com in
        # ASCII is meaningless. We judge the unicode form when we get it and
        # stay silent on the encoded one.
        return nil if typed.split('.').any? { |label| label.start_with?('xn--') }

        threshold = Nondisposable.configuration.lookalike_distance.to_i
        return nil if threshold < 1

        best = nil
        best_distance = threshold + 1

        providers.each do |candidate|
          # Cheap rejection before the O(n*m) walk: an edit changes the length
          # by at most 1 per operation, so anything further apart than the
          # threshold in length alone cannot be within it.
          next if (candidate.length - typed.length).abs > threshold

          distance = osa_distance(typed, candidate, best_distance)
          next if distance >= best_distance
          next unless plausible?(typed, candidate, distance)

          best = candidate
          best_distance = distance
          break if distance == 1 # nothing plausible can beat one edit; stop early
        end

        best
      end

      # Every domain we would suggest, as a frozen Set: the bundled list plus
      # anything the host added. Memoised per configuration object so a host
      # changing config in a test or console is picked up.
      def providers
        config = Nondisposable.configuration
        extra = Array(config.additional_email_providers).map { |d| Domain.normalize(d) }
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

      # Does the difference between what was typed and this provider look like
      # a slip of the finger? The two filters from the header, in code.
      def plausible?(typed, candidate, distance)
        name = candidate.split('.').first
        # The dot itself missed or swapped for a letter (`gmailmcom`,
        # `gmailcom`): nobody owns a domain shaped like that, and the TLD path
        # refuses it anyway, so it is always worth naming the correction.
        return true if typed.count('.') < candidate.count('.') && typed.start_with?(name)

        inside_name = typed.split('.').first != name
        return false if inside_name && name.length <= SHORT_NAME_LENGTH
        # The edit model below describes ONE edit. A host that widened
        # lookalike_distance has opted into coarser guesses; filter 1 still
        # applies, filter 2 has nothing to say.
        return true if distance > 1

        finger_slip?(typed, candidate)
      end

      # One edit, classified — in the name or after it, the same fingers type
      # both (`gmail.cpm` is as plausible as `gmsil.com`, `yahoo.com.au` as
      # implausible as `grail.com`). Callers have already established the
      # distance is exactly 1, so exactly one of these shapes applies.
      def finger_slip?(typed, candidate)
        i = 0
        i += 1 while i < typed.length && i < candidate.length && typed[i] == candidate[i]

        case typed.length - candidate.length
        when -1
          # A dropped letter (`gmal`, `hotmal`, `gmail.co`) — but not the
          # first one: `cloud.com`, `aver.com` and `mail.ch` are what
          # dropping the first letter of icloud, naver and gmail.ch spells,
          # and every one of them is somebody's real domain.
          i.positive?
        when 1
          # An extra letter is a slip when it repeats, or sits next to, a
          # letter it was typed beside (`gmmail`, `gmaiul` — not `mlive`), or
          # when it is a vowel: spelling by ear adds vowels (`gamail`,
          # `gimail`) far more often than consonants.
          extra = typed[i]
          return true if VOWELS.include?(extra)

          beside = [i.positive? ? typed[i - 1] : nil, typed[i + 1]].compact
          beside.any? { |near| near == extra || neighbours?(near, extra) }
        else
          # A swap (`gmial`) is the one mistake OSA counts as one edit…
          return true if typed[i + 1] == candidate[i] && typed[i] == candidate[i + 1]

          # …otherwise it is a substitution, which has to be a neighbouring
          # key — or the same key with an accent (`gmaíl`: on a Spanish
          # keyboard í is i after a dead key, not a different letter).
          same_key?(typed[i], candidate[i]) || neighbours?(typed[i], candidate[i])
        end
      end

      def same_key?(a, b)
        a.unicode_normalize(:nfd)[0] == b.unicode_normalize(:nfd)[0]
      end

      def neighbours?(a, b)
        keyboard.fetch(a, nil)&.include?(b) || false
      end

      # key => the keys around it, on a staggered QWERTY: the row's own left and
      # right, and the two keys above and below that it physically touches.
      def keyboard
        @keyboard ||= begin
          map = Hash.new { |h, k| h[k] = Set.new }
          KEYBOARD_ROWS.each_with_index do |row, r|
            row.each_char.with_index do |key, c|
              touching = [[r, c - 1], [r, c + 1], [r - 1, c], [r - 1, c + 1], [r + 1, c - 1], [r + 1, c]]
              touching.each do |rr, cc|
                next if rr.negative? || cc.negative? || rr >= KEYBOARD_ROWS.size

                other = KEYBOARD_ROWS[rr][cc]
                map[key] << other if other
              end
            end
          end
          map.default_proc = nil
          map.freeze
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
