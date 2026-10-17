# frozen_string_literal: true

module Nondisposable
  # One answer to "is this the same domain?", shared by every path that
  # compares a domain against a list.
  #
  # Before this existed each path trimmed its input its own way: the suggestion
  # layer stripped a trailing dot and the database check did not, so
  # `user@gmial.com.` and `user@gmial.com` could get different verdicts from the
  # same gem. Anything that matches a domain against a list — bundled, host
  # configured or downloaded — should go through #normalize first, so that two
  # spellings of one host can never be judged differently.
  #
  # WHAT IT DOES
  #
  #   Nondisposable::Domain.normalize("  GMail.COM. ")     # => "gmail.com"
  #   Nondisposable::Domain.normalize("bücher.de")         # => "xn--bcher-kva.de"
  #   Nondisposable::Domain.normalize("XN--BCHER-KVA.DE")  # => "xn--bcher-kva.de"
  #   Nondisposable::Domain.from_email("First+tag@GMail.com") # => "gmail.com"
  #
  # Only the DOMAIN is ever touched. The local part is case-sensitive under
  # RFC 5321 and `+tags` are the user's business; nothing here reads or
  # rewrites them.
  #
  # WHY PUNYCODE, AND WHY NO DEPENDENCY
  #
  # A unicode domain and its punycode form are the same host (`bücher.de` ==
  # `xn--bcher-kva.de`), and lists store the ASCII form, so matching has to
  # happen in ASCII. The `simpleidn` / `addressable` gems would do it, but the
  # encoding itself (RFC 3492) is forty lines of arithmetic and this gem ships
  # with no runtime dependencies beyond Rails. What we deliberately do NOT
  # implement is the full IDNA2008/UTS #46 validity table (which code points
  # are disallowed): we map — NFKC, lowercase, the ideographic full stops, the
  # invisible characters UTS #46 drops — and
  # encode, and leave "is this label legal" to the DNS. For matching that is
  # the right trade: a domain we encode that the registry would have refused
  # cannot be on anybody's list either.
  module Domain
    # The label separators UTS #46 treats as a full stop: ideographic,
    # fullwidth and halfwidth ideographic. A user on a CJK keyboard types these.
    DOTS = /[。．｡]/.freeze

    # Characters UTS #46 maps to nothing: soft hyphen, zero-width space and
    # joiners, word joiner, BOM, combining grapheme joiner, variation
    # selectors. Invisible in a form field, so `maili<SHY>nator.com` would
    # otherwise be a different string from the listed `mailinator.com`.
    IGNORED = /[­͏᠋-᠍​-‍⁠︀-️﻿]/.freeze

    # RFC 3492 §5: the bootstring parameters that make it punycode.
    BASE = 36
    TMIN = 1
    TMAX = 26
    SKEW = 38
    DAMP = 700
    INITIAL_BIAS = 72
    INITIAL_N = 128
    private_constant :BASE, :TMIN, :TMAX, :SKEW, :DAMP, :INITIAL_BIAS, :INITIAL_N

    class << self
      # The canonical, ASCII form of a domain: stripped, lowercased, without a
      # trailing root dot, unicode labels punycode-encoded. "" for blank input,
      # never nil, so callers can chain without guarding.
      def normalize(domain)
        value = unicode(domain)
        return value if value.ascii_only?
        # DNS caps a name at 253 octets and a label at 63, and the encoder
        # below is quadratic in the distinct code points of a label — so a
        # 4,000-character label typed into a signup form (or shipped in a
        # downloaded list) would cost seconds. Nothing that long can be a
        # registered domain or match a stored row; hand it back unencoded.
        return value if value.length > 253 || value.split('.', -1).any? { |label| label.length > 63 }

        value.split('.', -1).map { |label| label.ascii_only? ? label : "xn--#{punycode(label)}" }.join('.')
      rescue ArgumentError, Encoding::CompatibilityError
        # Bytes that are not valid UTF-8 cannot be a domain anybody typed; keep
        # a stable, comparable form instead of raising inside a validator.
        domain.to_s.b.strip.downcase.delete_suffix('.')
      end

      # The same canonicalisation WITHOUT the punycode step, for code that
      # compares what a human typed (the suggestion layer: a keyboard slip is a
      # distance between the characters someone pressed, and punycode letters
      # have no keyboard meaning — `xn--gmal-zqa` is `gmaíl`).
      def unicode(domain)
        value = domain.to_s.strip
        # NFKC, not NFC: it also folds compatibility forms, so fullwidth
        # `ｇｍａｉｌ` is `gmail` — the mapping UTS #46 applies before lookup.
        value = value.gsub(IGNORED, '').unicode_normalize(:nfkc) unless value.ascii_only?
        value.gsub(DOTS, '.').downcase.delete_suffix('.')
      end

      # The domain half of an address, normalised. Splits on the LAST "@", so a
      # quoted local part containing one (`"a@b"@example.com`) still yields the
      # right domain. "" when there is no "@" or nothing after it. An empty
      # local part (`@tempmail.com`) still has a domain worth judging, so it
      # is not this method's place to refuse it.
      def from_email(email)
        _local, at, domain = email.to_s.rpartition('@')
        return '' if at.empty?

        normalize(domain)
      end

      private

      # RFC 3492 §6.3, the encoder only: we never need to decode.
      def punycode(label)
        input = label.codepoints
        output = input.select { |c| c < 0x80 }.pack('U*')
        basic = output.length
        handled = basic
        output += '-' if basic.positive?

        n = INITIAL_N
        delta = 0
        bias = INITIAL_BIAS

        while handled < input.length
          m = input.select { |c| c >= n }.min
          delta += (m - n) * (handled + 1)
          n = m

          input.each do |c|
            delta += 1 if c < n
            next unless c == n

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
            bias = adapt(delta, handled + 1, handled == basic)
            delta = 0
            handled += 1
          end

          delta += 1
          n += 1
        end

        output
      end

      def threshold(k, bias)
        return TMIN if k <= bias
        return TMAX if k >= bias + TMAX

        k - bias
      end

      def digit(d)
        (d < 26 ? d + 97 : d + 22).chr
      end

      def adapt(delta, points, first)
        delta = first ? delta / DAMP : delta / 2
        delta += delta / points
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
