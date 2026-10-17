# frozen_string_literal: true

require 'set'

module Nondisposable
  # One upstream blocklist, described well enough to decide how far to trust it.
  #
  # TRUST
  #
  #   :primary        every domain it lists is blocked (subject to the
  #                   precedence table, see Nondisposable::Precedence)
  #   :corroborating  a domain it lists is blocked only once
  #                   config.corroboration_threshold independent ORIGINS list it
  #
  # LINEAGE, AND WHY TWO LISTS ARE OFTEN ONE OBSERVATION
  #
  # Public blocklists copy each other. `disposable/disposable-email-domains`
  # declares that it imports mailchecker, fakefilter, wesbos, unkn0w and the
  # original disposable-email-domains list; groundcat imports
  # disposable/disposable among others. Counting "two repositories list it" as
  # two votes would let one mistaken line acquire as many votes as it has
  # copies. So each source declares what it is `derived_from`, and a source's
  # vote for a domain only counts when none of its (transitive) upstreams that
  # we also loaded carries the same domain. See Nondisposable::SourceMerge.
  #
  # Declared lineage is the only lineage we know about. Two lists that copy each
  # other without saying so still look independent, which is one more reason
  # the recommended preset leans on primaries and keeps corroboration strict.
  class Source
    TRUST_LEVELS = %i[primary corroborating].freeze

    # Generous for the largest list we know of (disposable/disposable, ~1.4 MB),
    # small enough that a runaway response cannot exhaust a worker's memory.
    DEFAULT_MAX_BYTES = 8 * 1024 * 1024
    # Wall-clock budget for the whole download of one source, in seconds.
    DEFAULT_DEADLINE = 30

    # Lines that fail to parse as a domain are dropped one by one. When more than
    # this share of the payload is junk, the payload is not a blocklist at all —
    # an HTML error page, a captive portal, a format change — and the whole
    # snapshot is refused rather than half-ingested.
    MAX_INVALID_RATIO = 0.01

    NAME_FORMAT = %r{\A[a-z0-9][a-z0-9._/-]*\z}

    ATTRIBUTES = %i[name url trust derived_from license homepage minimum_count max_bytes deadline bundled_path].freeze
    attr_reader(*ATTRIBUTES)

    # Accepts a Source, or a Hash of its attributes (what a host writes in an
    # initializer). Raises ArgumentError on anything it cannot trust.
    def self.build(value)
      return value if value.is_a?(Source)
      raise ArgumentError, "a source must be a Nondisposable::Source or a Hash (got #{value.inspect})" unless value.is_a?(Hash)

      new(**value.transform_keys(&:to_sym))
    end

    def initialize(name:, url:, trust: :corroborating, derived_from: [], license: nil, homepage: nil,
                   minimum_count: 1, max_bytes: DEFAULT_MAX_BYTES, deadline: DEFAULT_DEADLINE, bundled_path: nil)
      @name = name.to_s
      @url = url.to_s
      @trust = trust.respond_to?(:to_sym) ? trust.to_sym : trust
      @derived_from = Array(derived_from).map(&:to_s).freeze
      @license = license
      @homepage = homepage
      @minimum_count = Integer(minimum_count)
      @max_bytes = Integer(max_bytes)
      @deadline = deadline
      @bundled_path = bundled_path

      validate!
      freeze
    end

    # A copy with some attributes replaced, e.g. promoting a preset source:
    #   Nondisposable::Sources::DISPOSABLE.with(trust: :primary)
    def with(**overrides)
      self.class.new(**to_h.merge(overrides))
    end

    def to_h
      ATTRIBUTES.to_h { |attribute| [attribute, public_send(attribute)] }
    end

    def primary?
      trust == :primary
    end

    def ==(other)
      other.is_a?(Source) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    Parsed = Struct.new(:domains, :lines, :invalid, :invalid_sample, keyword_init: true) do
      def invalid_ratio
        lines.zero? ? 0.0 : invalid.fdiv(lines)
      end
    end

    # Plain text, one domain per line. `#` starts a comment (whole-line or
    # inline), blank lines are ignored, and every entry goes through
    # Domain.normalize. Entries that are not a possible DNS name are counted
    # and dropped; public suffixes are kept here (the snapshot records what the
    # source said) and dropped by the precedence filter when the list is built.
    #
    # Returns sorted, unique, canonical domains: the count every guard is
    # measured on, so duplicates and casing cannot inflate it.
    def self.parse(body)
      domains = Set.new
      lines = 0
      invalid = 0
      sample = []

      body.to_s.each_line do |line|
        entry = line.sub(/#.*/, '').strip
        next if entry.empty?

        lines += 1
        domain = Domain.normalize(entry)
        if Precedence.hostname?(domain)
          domains << domain
        else
          invalid += 1
          sample << entry[0, 80] if sample.size < 5
        end
      end

      Parsed.new(domains: domains.to_a.sort, lines: lines, invalid: invalid, invalid_sample: sample)
    end

    private

    def validate!
      raise ArgumentError, "source name #{name.inspect} must match #{NAME_FORMAT.inspect}" unless NAME_FORMAT.match?(name)
      raise ArgumentError, "source #{name}: trust must be one of #{TRUST_LEVELS.inspect} (got #{trust.inspect})" unless TRUST_LEVELS.include?(trust)
      # Plain http would let anybody on the path rewrite the blocklist.
      raise ArgumentError, "source #{name}: url must be https (got #{url.inspect})" unless url.start_with?('https://')
      raise ArgumentError, "source #{name}: max_bytes must be positive" unless max_bytes.positive?
      raise ArgumentError, "source #{name}: minimum_count must be at least 1" unless minimum_count >= 1
      raise ArgumentError, "source #{name}: deadline must be a positive number of seconds" unless deadline.is_a?(Numeric) && deadline.positive?
      raise ArgumentError, "source #{name} cannot be derived from itself" if derived_from.include?(name)
    end
  end

  # The sources we have measured, with their licences and declared lineage.
  # Measurements (2026-10-17) and the reasoning behind every trust level:
  # docs/evidence/2026-10-17-multi-source-measurement.md
  module Sources
    # The list this gem has always used, and the one bundled as the seed.
    DISPOSABLE_EMAIL_DOMAINS = Source.new(
      name: 'disposable-email-domains',
      url: 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf',
      homepage: 'https://github.com/disposable-email-domains/disposable-email-domains',
      license: 'CC0-1.0',
      trust: :primary,
      minimum_count: 1_000,
      bundled_path: File.expand_path('../../data/disposable_email_blocklist.conf', __dir__)
    )

    # Monitors temp-mail generators directly and publishes what they hand out.
    # 0 known-real providers measured in it.
    FAKEFILTER = Source.new(
      name: 'fakefilter',
      url: 'https://raw.githubusercontent.com/7c/fakefilter/main/txt/data.txt',
      homepage: 'https://github.com/7c/fakefilter',
      license: 'BSD-3-Clause',
      trust: :primary,
      minimum_count: 1_000
    )

    MAILCHECKER = Source.new(
      name: 'mailchecker',
      url: 'https://raw.githubusercontent.com/FGRibreau/mailchecker/master/list.txt',
      homepage: 'https://github.com/FGRibreau/mailchecker',
      license: 'MIT',
      trust: :corroborating,
      minimum_count: 1_000
    )

    WESBOS = Source.new(
      name: 'wesbos',
      url: 'https://raw.githubusercontent.com/wesbos/burner-email-providers/master/emails.txt',
      homepage: 'https://github.com/wesbos/burner-email-providers',
      license: 'MIT',
      trust: :corroborating,
      minimum_count: 1_000
    )

    # The broadest maintained list (~97k) and the only one that carried
    # mail-burn.com on 2026-10-17 — but as a PRIMARY it also blocks real mail
    # providers (China Unicom's wo.com.cn, the Japanese ISP odn.ad.jp, ...), so
    # it is corroborating by default. Promote it knowingly:
    #   Nondisposable::Sources::DISPOSABLE.with(trust: :primary)
    DISPOSABLE = Source.new(
      name: 'disposable',
      url: 'https://raw.githubusercontent.com/disposable/disposable-email-domains/master/domains.txt',
      homepage: 'https://github.com/disposable/disposable',
      license: 'MIT',
      trust: :corroborating,
      derived_from: %w[disposable-email-domains fakefilter mailchecker wesbos unkn0w],
      minimum_count: 1_000
    )

    GROUNDCAT = Source.new(
      name: 'groundcat',
      url: 'https://raw.githubusercontent.com/groundcat/disposable-email-domain-list/master/domains.txt',
      homepage: 'https://github.com/groundcat/disposable-email-domain-list',
      license: 'MIT',
      trust: :corroborating,
      derived_from: %w[disposable-email-domains disposable mailchecker ivolo emailondeck],
      minimum_count: 1_000
    )

    # Today's behaviour: the one list this gem has always used.
    DEFAULT = [DISPOSABLE_EMAIL_DOMAINS].freeze

    # Two primaries that observe generators independently. +3,275 domains over
    # DEFAULT on 2026-10-17, none of them a known real provider.
    #
    # Why no corroborating sources: with lineage declared, disposable,
    # mailchecker and groundcat are each explained by an upstream already
    # loaded, so together they added ZERO domains for three more downloads a
    # day. Adding wesbos (no declared lineage, but 57% of it is also in
    # mailchecker) "corroborated" 11,751 more, among them real providers such
    # as tom.com and sdf.org. Add corroborating sources once a genuinely
    # independent list exists; the machinery is ready.
    RECOMMENDED = [DISPOSABLE_EMAIL_DOMAINS, FAKEFILTER].freeze
  end
end
