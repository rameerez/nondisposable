# frozen_string_literal: true

require 'set'

module Nondisposable
  # Turns each source's last good snapshot into one list of blocked domains.
  #
  #   blocked = every domain in any PRIMARY source
  #           + every domain that at least `threshold` independent ORIGINS
  #             among the CORROBORATING sources list
  #
  # An origin is a source whose vote is not explained by an upstream: for a
  # domain listed by A and B, where A declares `derived_from: [B]`, only B
  # counts. Lineage is followed transitively (groundcat → disposable →
  # mailchecker), and only through sources that were actually loaded — an
  # upstream we did not fetch cannot explain anything, so the downstream's vote
  # stands.
  #
  # Known blind spot, documented rather than guessed at: if an upstream REMOVES
  # a domain (a fixed false positive) and a downstream still carries its stale
  # copy, the copy now looks like an independent observation. With the default
  # threshold of 2 that alone cannot block anything.
  #
  # Pure: no database, no configuration, no logging. The precedence table is
  # applied afterwards (Nondisposable::Precedence.filter).
  module SourceMerge
    Result = Struct.new(:domains, :primary_count, :corroborated_count, keyword_init: true)

    class << self
      # `snapshots` is { Source => Array<String> (normalized domains) }.
      def call(snapshots, threshold:)
        threshold = Integer(threshold)
        raise ArgumentError, 'corroboration_threshold must be at least 1' if threshold < 1

        primaries, corroborating = snapshots.partition { |source, _| source.primary? }

        blocked = Set.new
        primaries.each { |_, domains| blocked.merge(domains) }
        primary_count = blocked.size

        names = snapshots.keys.map(&:name).to_set
        ancestors = ancestry(snapshots.keys, names)

        votes = Hash.new { |hash, key| hash[key] = [] }
        corroborating.each do |source, domains|
          domains.each { |domain| votes[domain] << source.name unless blocked.include?(domain) }
        end

        corroborated = 0
        votes.each do |domain, voters|
          next if voters.size < threshold # cannot reach it even before lineage

          present = voters.to_set
          origins = voters.count { |voter| !ancestors[voter].intersect?(present) }
          next if origins < threshold

          blocked << domain
          corroborated += 1
        end

        Result.new(domains: blocked, primary_count: primary_count, corroborated_count: corroborated)
      end

      # How many independent origins vote for `domain`. For explaining a
      # verdict in a console, not used by #call's fast path.
      def origins_for(domain, snapshots)
        names = snapshots.keys.map(&:name).to_set
        ancestors = ancestry(snapshots.keys, names)
        present = snapshots.select { |_, domains| domains.include?(domain) }.keys.map(&:name).to_set
        present.reject { |name| ancestors[name].intersect?(present) }.sort
      end

      private

      # { source name => Set of every loaded upstream, transitively }.
      def ancestry(sources, loaded)
        declared = sources.to_h { |source| [source.name, source.derived_from] }
        declared.keys.to_h do |name|
          seen = Set.new
          stack = declared[name].dup
          until stack.empty?
            upstream = stack.pop
            next if seen.include?(upstream)

            seen << upstream
            stack.concat(declared.fetch(upstream, []))
          end
          [name, seen & loaded]
        end
      end
    end
  end
end
