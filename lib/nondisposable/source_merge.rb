# frozen_string_literal: true

require 'set'

module Nondisposable
  # Turns each source's last good snapshot into one list of blocked domains.
  #
  #   blocked = every domain in any PRIMARY source
  #           + every domain that at least `threshold` independent ORIGINS
  #             among the CORROBORATING sources list
  #
  # Votes are counted per INDEPENDENT ORIGIN. Two voters are RELATED when one
  # declares the other as an upstream, or both declare a common upstream
  # (transitively, including upstreams we did not load: two mirrors of the
  # same unfetched list are one observation, not two). A domain's origin
  # count is the largest set of pairwise-unrelated voters. A list that merely
  # copies two independent lists does not make them related, and adds no vote.
  #
  # Known blind spot: lineage is only what sources DECLARE. Two lists that copy
  # each other silently (wesbos and mailchecker overlap by 57%) still look
  # independent; that is why the recommended preset uses no corroborating
  # sources at all.
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

        ancestors = ancestry(snapshots.keys)

        votes = Hash.new { |hash, key| hash[key] = [] }
        corroborating.each do |source, domains|
          domains.each { |domain| votes[domain] << source.name unless blocked.include?(domain) }
        end

        corroborated = 0
        votes.each do |domain, voters|
          next if voters.size < threshold # cannot reach it even before lineage

          next if independent_origins(voters, ancestors).size < threshold

          blocked << domain
          corroborated += 1
        end

        Result.new(domains: blocked, primary_count: primary_count, corroborated_count: corroborated)
      end

      # How many independent origins vote for `domain`. For explaining a
      # verdict in a console, not used by #call's fast path.
      # A largest set of pairwise-unrelated sources voting for `domain`
      # (alphabetically first among ties). For explaining a verdict in a
      # console; #call uses the same rule.
      def origins_for(domain, snapshots)
        voters = snapshots.select { |_, domains| domains.include?(domain) }.keys.map(&:name)
        independent_origins(voters, ancestry(snapshots.keys))
      end

      private

      # Brute force over subsets, largest first: there are only ever a handful
      # of corroborating sources, and most domains have one or two voters.
      def independent_origins(voters, ancestors)
        voters = voters.sort
        related = lambda do |a, b|
          ancestors[a].include?(b) || ancestors[b].include?(a) || ancestors[a].intersect?(ancestors[b])
        end

        voters.size.downto(1) do |size|
          voters.combination(size) do |subset|
            return subset if subset.combination(2).none? { |a, b| related.call(a, b) }
          end
        end
        []
      end

      # { source name => Set of every declared upstream, transitively,
      # loaded or not }.
      def ancestry(sources)
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
          [name, seen]
        end
      end
    end
  end
end
