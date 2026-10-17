# frozen_string_literal: true

module Nondisposable
  # The ONE place a domain becomes comparable.
  #
  # Every path that matches a domain against a list — configuration, list
  # ingestion, `disposable?`, the TLD check and suggestions — must agree on what
  # "the same domain" means, or a list can say one thing and a check another:
  # `Tempmail.com.` and `tempmail.com` are the same host, and so are
  # `bücher.de` and `xn--bcher-kva.de`.
  #
  # Only ever the domain: the local part of an address (case, `+tags`) is the
  # mailbox owner's business and is never touched here.
  module Domain
    # Punycode parameters, RFC 3492 §5.
    BASE = 36
    TMIN = 1
    TMAX = 26
    SKEW = 38
    DAMP = 700
    INITIAL_BIAS = 72
    INITIAL_N = 0x80
    ACE_PREFIX = 'xn--'

    class << self
      # Stripped, without a trailing dot, case-folded, and in ASCII: each
      # non-ASCII label is NFKC-normalized, downcased and punycode-encoded.
      # Returns "" for blank input. Never raises on odd input — a label that
      # cannot be encoded is returned downcased as-is, which matches nothing.
      def normalize(domain)
        value = domain.to_s.strip.delete_suffix('.')
        return '' if value.empty?
        return value.downcase if value.ascii_only?

        value.unicode_normalize(:nfkc).downcase.split('.', -1).map { |label| to_ascii(label) }.join('.')
      rescue StandardError
        domain.to_s.strip.delete_suffix('.').downcase
      end

      private

      def to_ascii(label)
        return label if label.ascii_only?

        ACE_PREFIX + punycode_encode(label)
      end

      # RFC 3492 §6.3, transcribed.
      def punycode_encode(input)
        code_points = input.codepoints
        output = code_points.select { |cp| cp < 0x80 }.pack('U*')
        basic_count = output.length
        handled = basic_count
        output << '-' if basic_count.positive?

        n = INITIAL_N
        delta = 0
        bias = INITIAL_BIAS

        while handled < code_points.length
          m = code_points.select { |cp| cp >= n }.min
          delta += (m - n) * (handled + 1)
          n = m

          code_points.each do |cp|
            delta += 1 if cp < n
            next unless cp == n

            q = delta
            k = BASE
            loop do
              t = threshold(k, bias)
              break if q < t

              output << digit(t + ((q - t) % (BASE - t)))
              q = (q - t) / (BASE - t)
              k += BASE
            end
            output << digit(q)
            bias = adapt(delta, handled + 1, handled == basic_count)
            delta = 0
            handled += 1
          end

          delta += 1
          n += 1
        end

        output
      end

      def threshold(k, bias)
        if k <= bias then TMIN
        elsif k >= bias + TMAX then TMAX
        else k - bias
        end
      end

      def digit(d)
        (d < 26 ? d + 97 : d + 22).chr
      end

      def adapt(delta, num_points, first_time)
        delta = first_time ? delta / DAMP : delta / 2
        delta += delta / num_points
        k = 0
        while delta > ((BASE - TMIN) * TMAX) / 2
          delta /= BASE - TMIN
          k += BASE
        end
        k + (((BASE - TMIN + 1) * delta) / (delta + SKEW))
      end
    end
  end
end
