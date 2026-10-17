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
  # invisible characters UTS #46 drops (nontransitionally: ZWJ/ZWNJ stay) — and
  # encode, and leave "is this label legal" to the DNS. For matching that is
  # the right trade: a domain we encode that the registry would have refused
  # cannot be on anybody's list either.
  module Domain
    # The label separators UTS #46 treats as a full stop: ideographic,
    # fullwidth and halfwidth ideographic. A user on a CJK keyboard types these.
    DOTS = /[。．｡]/.freeze

    # Every code point UTS #46 maps to nothing ("ignored" in
    # IdnaMappingTable.txt, Unicode 2026-06-29): soft hyphen, combining
    # grapheme joiner, Hangul and Khmer fillers, Mongolian variation selectors,
    # zero-width space, word joiner and invisible operators, variation
    # selectors 1–256, BOM, shorthand format controls, musical beam controls.
    # Invisible in a form field, so `maili<SHY>nator.com` would otherwise be a
    # different string from the listed `mailinator.com` — while a mail server
    # applying IDNA would deliver it to mailinator.com.
    #
    # ZWNJ and ZWJ (U+200C/D) are deliberately NOT here. UTS #46 lists them as
    # "deviation" characters, and nontransitional processing (IDNA2008, what
    # registries and browsers use) keeps them: `نامه‌ای.com` with a ZWNJ is a
    # different registered domain from the same letters without one.
    IGNORED = /[­͏ᅟᅠ឴឵᠋-᠏​⁠-⁤⁪-⁯ㅤ︀-️﻿ﾠ\u{1BCA0}-\u{1BCA3}\u{1D173}-\u{1D17A}\u{E0100}-\u{E01EF}]/.freeze

    # DNS caps a name at 253 octets (RFC 1035 §2.3.4) and a label at 63, and
    # the punycode encoder is quadratic in a label's distinct code points, so
    # #normalize hands anything longer back unencoded: it cannot be a
    # registered domain or match a stored row. The cap applies to the
    # NORMALISED name — `e` + combining acute is two code points that NFKC
    # composes into one `é`, so a valid 32-letter label can arrive as 64.
    MAX_LENGTH = 253
    MAX_LABEL_LENGTH = 63

    # The bounds on what is fed to NFKC, which is superlinear on hostile input
    # (a long run of combining marks to reorder). 1,024 code points is four
    # per allowed character — room for any real decomposition (Hangul jamo
    # take three) — and matches DisposableDomain::MAX_INPUT_LENGTH. A run of
    # more than 30 combining marks is not stream-safe text (UAX #15 §13), so
    # no registered label contains one and it is not worth normalising.
    MAX_RAW_LENGTH = 1_024
    UNSTREAMSAFE = /\p{M}{31,}/.freeze


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
        return value if value.ascii_only? || value.encoding == Encoding::BINARY
        # The punycode encoder is quadratic in the distinct code points of a
        # label: a 4,000-character label would cost seconds. Over DNS's limits
        # it cannot be a registered domain; hand it back unencoded.
        return value if oversized?(value)

        value.split('.', -1).map { |label| label.ascii_only? ? label : "xn--#{punycode(label)}" }.join('.')
      end

      # Longer than DNS allows once normalised — over 253 characters, a label
      # over 63, or more than MAX_RAW_LENGTH code points before NFKC could
      # even run? Such a name cannot be registered, so no address at it can
      # receive mail, and no list can hold it: callers must treat it as
      # invalid rather than as "not disposable". Judged on the punycode form,
      # since a label that fits in unicode can still encode past 63.
      def too_long?(domain)
        oversized?(normalize(domain))
      end

      # The same canonicalisation WITHOUT the punycode step, for code that
      # compares what a human typed (the suggestion layer: a keyboard slip is a
      # distance between the characters someone pressed, and punycode letters
      # have no keyboard meaning — `xn--gmal-zqa` is `gmaíl`). Never raises.
      def unicode(domain)
        value = utf8(domain.to_s)
        # Bytes that are not UTF-8 cannot be a domain anybody typed: keep a
        # stable, comparable binary form instead of raising inside a validator.
        return value.strip.downcase.delete_suffix('.') if value.encoding == Encoding::BINARY

        value = value.strip
        return value.downcase.delete_suffix('.') if value.ascii_only?

        # Linear passes first, so the raw bound below sees what is left once
        # the invisible padding is gone (300 soft hyphens around
        # mailinator.com must not buy an exemption). The DNS limits are
        # enforced by #normalize on the result, after NFKC has composed it.
        value = value.gsub(IGNORED, '').gsub(DOTS, '.')
        return value.downcase.delete_suffix('.') if value.length > MAX_RAW_LENGTH || value.match?(UNSTREAMSAFE)

        # NFKC, not NFC: it also folds compatibility forms, so fullwidth
        # `ｇｍａｉｌ` is `gmail` — the mapping UTS #46 applies before lookup.
        value.unicode_normalize(:nfkc).gsub(DOTS, '.').downcase.delete_suffix('.')
      end

      # The domain half of an address, normalised. Splits on the LAST "@", so a
      # quoted local part containing one (`"a@b"@example.com`) still yields the
      # right domain. "" when there is no "@" or nothing after it. An empty
      # local part (`@tempmail.com`) still has a domain worth judging, so it
      # is not this method's place to refuse it.
      #
      # `unicode: true` returns the #unicode form instead of the punycode one:
      # what DisposableDomain needs to also match rows 0.4.0 stored unencoded.
      def from_email(email, unicode: false)
        email = email.to_s
        email = email.b unless email.valid_encoding? # unreadable bytes must not raise
        _local, at, domain = email.rpartition('@')
        return '' if at.empty?

        unicode ? unicode(domain) : normalize(domain)
      end

      private

      # A String in UTF-8 when its bytes are UTF-8, whatever encoding it was
      # labelled with: a form param or a log line handed over as ASCII-8BIT is
      # still `bücher.de`, and 0.4.0 accepted it without raising.
      def utf8(value)
        return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?

        copy = value.dup.force_encoding(Encoding::UTF_8)
        copy.valid_encoding? ? copy : value.b # BINARY: "not UTF-8"
      end

      def oversized?(value)
        value.length > MAX_LENGTH || value.split('.', -1).any? { |label| label.length > MAX_LABEL_LENGTH }
      end


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
