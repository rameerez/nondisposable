# frozen_string_literal: true

require 'digest'
require 'monitor'
require 'set'

module Nondisposable
  # Keeps nondisposable_disposable_domains current.
  #
  # TWO PATHS, CHOSEN BY THE SCHEMA
  #
  # - With the nondisposable_source_snapshots table (fresh installs from 0.6.0,
  #   or `rails g nondisposable:upgrade`): every source in config.sources is
  #   fetched into its own snapshot, then the stored list is REBUILT from each
  #   source's last good snapshot (#publish). One bad source costs its own
  #   update, never the list.
  # - Without it: the single-source behaviour of 0.5 and earlier — fetch the
  #   default list and replace the table. Rolling deploys are safe in both
  #   directions: new code before the migration takes this path, and old code
  #   after the migration simply never looks at the new table.
  #
  # Both paths go through the same precedence table (Nondisposable::Precedence)
  # and the same writer, under the same lock.
  #
  # WHAT IS NEVER PUBLISHED
  #
  # An empty list; a list built while any PRIMARY source has never been fetched
  # successfully (on a first run that would replace the bundled seed with less
  # than it); public suffixes; never-disposable domains; anything that is not a
  # possible domain name.
  class DomainListUpdater
    LIST_URL = Sources::DISPOSABLE_EMAIL_DOMAINS.url

    # Snapshot of the upstream blocklist vendored into the gem, used to seed
    # fresh installs so they are protected before the first remote update.
    BUNDLED_LIST_PATH = Sources::DISPOSABLE_EMAIL_DOMAINS.bundled_path

    # Network timeouts (seconds). Without these, a hung connection would block
    # the calling job/thread indefinitely (Net::HTTP defaults to 60s open / 60s read).
    OPEN_TIMEOUT = SourceFetcher::OPEN_TIMEOUT
    READ_TIMEOUT = SourceFetcher::READ_TIMEOUT

    # A fresh snapshot is refused when it holds fewer than half the domains of
    # the largest snapshot we still retain for that source, or more than three
    # times the last good one. Upstream lists change by a few percent a week;
    # anything bigger is an outage, a truncation or a format change until a
    # human says otherwise. Comparing against the retained MAXIMUM (not just
    # the previous run) is what stops a series of 49% cuts from ratcheting a
    # list down to nothing.
    MAX_SHRINK_RATIO = 0.5
    MAX_GROWTH_FACTOR = 3

    # Serializes publish and seed across processes. Any stable 63-bit integer;
    # this one spells "nondisp" in ASCII, so it is easy to spot in pg_locks.
    PUBLISH_LOCK_ID = 0x6e6f6e64697370
    PUBLISH_LOCK_WAIT = 30

    INSERT_BATCH_SIZE = 5_000
    LOG_PREVIEW = 20

    PROCESS_LOCK = Monitor.new
    private_constant :PROCESS_LOCK

    class << self
      # Returns true when every source was refreshed and the list published.
      # Never raises: a failure is logged, and an empty table is seeded from
      # the bundled snapshot so a broken network never means no protection.
      def update
        log :info, 'Refreshing list of disposable domains...'

        if SourceSnapshot.available?
          update_from_sources
        else
          update_single_source
        end
      rescue StandardError => e
        log :error, "An error occurred when trying to update the list of disposable domains: #{e.class}: #{e.message}"
        seed
        false
      end

      # Rebuilds the stored list from each configured source's last good
      # snapshot, without fetching anything. Run it after changing
      # excluded_domains, additional_domains, block_privacy_relays or sources,
      # or after a rollback. Returns true when it published.
      def publish
        with_publish_lock { publish! } || false
      end

      # Withdraws a source's newest good snapshot (marking it `rolled_back`, so
      # the same payload is refused if upstream serves it again) and republishes
      # from the one before. The emergency brake for a poisoned upstream; a
      # permanent fix is excluding the domain, or removing the source.
      #
      # If nothing good is left for any primary, the list bundled with the gem
      # stands in, even over a populated table: a rollback must always end
      # with the withdrawn list unpublished.
      def rollback(source_name)
        with_publish_lock do
          # Chosen INSIDE the lock: a refresh accepted between choosing and
          # locking would otherwise survive the rollback it raced.
          snapshot = SourceSnapshot.last_good(source_name.to_s)
          unless snapshot
            log :error, "Nothing to roll back: source #{source_name} has no good snapshot."
            next false
          end

          snapshot.update!(status: 'rolled_back')
          log :warn, "Rolled back #{source_name} snapshot ##{snapshot.id} (#{snapshot.domain_count} domains, fetched #{snapshot.fetched_at})."
          # A withdrawn source with no older good snapshot is simply left out:
          # keeping its poisoned list published would defeat the rollback.
          publish!(withdrawn: source_name.to_s)
        end || false
      end

      # Accepts that a source really did shrink: resets its high-water mark to
      # its current good snapshot, so the shrink guard measures from there.
      # A human decision by design; nothing calls it automatically. The count
      # is recomputed from that snapshot's payload, never copied from a
      # stored figure that an older rule may have produced.
      def reset_baseline(source_name)
        with_publish_lock do
          snapshot = SourceSnapshot.last_good(source_name.to_s)
          next false unless snapshot

          count = storable_count(snapshot.domain_list)
          attributes = { domain_count: count }
          attributes[:high_water_count] = count if high_water_column?
          snapshot.update!(attributes)
          log :warn, "Reset the #{source_name} shrink baseline to #{count} domains."
          true
        end || false
      end

      # Seeds the domain table from the blocklist snapshot bundled with the gem,
      # but ONLY when the table is empty. This closes the fresh-install fail-open
      # window where every email passed validation until the first successful
      # remote update. Returns true if it seeded, false otherwise.
      #
      # The bundled list is a snapshot from the gem's release date — always run
      # DomainListUpdater.update (e.g. via the provided job) to stay current.
      def seed
        with_publish_lock { seed! } || false
      rescue StandardError => e
        log :error, "Could not seed from the bundled list: #{e.message}"
        false
      end

      # config.sources as validated Source objects. Raises ArgumentError on a
      # configuration we cannot honour, so a typo fails loudly in the log
      # instead of silently shrinking the list.
      def configured_sources
        sources = Array(Nondisposable.configuration.sources).map { |source| Source.build(source) }
        raise ArgumentError, 'config.sources is empty' if sources.empty?

        [[:name, 'name'], [:url, 'URL']].each do |attribute, label|
          dupes = sources.map(&attribute).tally.select { |_, count| count > 1 }.keys
          raise ArgumentError, "config.sources lists the same #{label} twice: #{dupes.join(', ')}" if dupes.any?
        end
        raise ArgumentError, 'config.sources needs at least one :primary source' if sources.none?(&:primary?)

        sources
      end

      private

      # ---- Multi-source path ------------------------------------------------

      def update_from_sources
        sources = configured_sources
        refreshed = sources.map { |source| refresh(source) }.all?
        published = publish
        refreshed && published
      end

      # Fetches one source into a snapshot row. Never raises.
      #
      # The download happens outside the publish lock (it can take a while);
      # judging it and recording the verdict happen inside, so a rollback or a
      # publish can never interleave with a snapshot being accepted.
      def refresh(source)
        fetched_at = Time.current
        parsed = Source.parse(SourceFetcher.fetch(source))
        with_publish_lock { accept(source, parsed) } || false
      rescue StandardError => e
        log :error, "Could not fetch #{source.name} (#{source.url}): #{e.class}: #{e.message}. Keeping its last good snapshot."
        begin
          record(source, 'failed', fetched_at || Time.current, error: "#{e.class}: #{e.message}"[0, 1_000])
        rescue StandardError => record_error
          log :error, "Could not record the failed #{source.name} fetch: #{record_error.message}"
        end
        false
      ensure
        begin
          with_publish_lock { SourceSnapshot.prune(source.name) }
        rescue StandardError => e
          log :warn, "Could not prune old #{source.name} snapshots: #{e.message}"
        end
      end

      # `fetched_at` is the ACCEPTANCE time, taken under the lock: snapshots
      # are ordered by when they were judged, so a slow job that finishes late
      # can never slot an older verdict above a newer one.
      def accept(source, parsed)
        fetched_at = Time.current
        sha256 = Digest::SHA256.hexdigest(parsed.domains.join("\n"))
        count = storable_count(parsed.domains)
        previous = SourceSnapshot.last_good(source.name)

        if (reason = guard(source, parsed, count, sha256, previous))
          log :error, "Refusing the new #{source.name} list: #{reason}. Keeping its last good snapshot."
          record(source, 'rejected', fetched_at, sha256: sha256, domain_count: count, error: reason)
          return false
        end

        if previous && previous.sha256 == sha256
          previous.update!(fetched_at: [previous.fetched_at, fetched_at].max)
          log :info, "#{source.name}: unchanged (#{count} domains)."
          return true
        end

        log_changes(source, previous, parsed)
        log_poison(source, parsed.domains)
        attributes = { sha256: sha256, domain_count: count, domains: parsed.domains.join("\n") }
        attributes[:high_water_count] = [high_water(source, previous), count].compact.max if high_water_column?
        record(source, 'ok', fetched_at, **attributes)
        true
      end

      # A snapshots table created by an earlier development build of this
      # branch has no high_water_count. Never crash a refresh over it: fall
      # back to the retained snapshots, and say so once per process.
      def high_water_column?
        present = SourceSnapshot.column_names.include?('high_water_count')
        unless present || @warned_high_water
          @warned_high_water = true
          log :warn, 'nondisposable_source_snapshots has no high_water_count column; the shrink guard falls back to ' \
                     'retained snapshots. Recreate the table from the current migration to restore it.'
        end
        present
      end

      # The domains of a list that would be stored under ANY host policy: not
      # junk, not a public suffix, not a known real provider, not a privacy
      # relay. Host settings (block_privacy_relays, excluded_domains,
      # additional_domains) are deliberately ignored, so every count of a source
      # is comparable with every other, before and after a policy change. Every
      # size guard counts THESE, so a payload padded with anything the filter
      # can drop cannot pass for a full list.
      def storable_count(domains)
        Precedence.filter(domains, host_policy: false).kept.size
      end

      # The largest storable count this source has ever had accepted, kept on
      # its newest good snapshot so pruning can never forget it. Without a
      # recorded mark yet: the largest retained count, or the bundled list.
      def high_water(source, previous = SourceSnapshot.last_good(source.name))
        recorded = previous&.high_water_count if high_water_column?
        return recorded if recorded # authoritative, and what reset_baseline lowers

        retained = SourceSnapshot.ok.where(source: source.name).maximum(:domain_count)
        [retained, bundled_count(source)].compact.max
      end

      # nil when the snapshot may be used, otherwise why not. `count` is the
      # storable count (see #storable_count); snapshot domain_counts are too.
      def guard(source, parsed, count, sha256, previous)
        return 'the list is empty' if count.zero?

        if parsed.invalid_ratio > Source::MAX_INVALID_RATIO
          return "#{parsed.invalid} of #{parsed.lines} lines are not domain names " \
                 "(e.g. #{parsed.invalid_sample.map(&:inspect).join(', ')}) — not a blocklist"
        end
        return "only #{count} domains (this source's minimum_count is #{source.minimum_count})" if count < source.minimum_count

        if SourceSnapshot.where(source: source.name, status: 'rolled_back', sha256: sha256).exists?
          return 'it is identical to a snapshot that was rolled back'
        end

        largest = high_water(source, previous)
        if largest && count < largest * MAX_SHRINK_RATIO
          return "it shrank to #{count} domains from #{largest} (more than #{(MAX_SHRINK_RATIO * 100).round}%)"
        end

        baseline = previous&.domain_count || bundled_count(source)
        if baseline && baseline >= source.minimum_count && count > baseline * MAX_GROWTH_FACTOR
          return "it grew to #{count} domains from #{baseline} (more than #{MAX_GROWTH_FACTOR}x)"
        end

        nil
      end

      def bundled_count(source)
        return nil unless source.bundled_path && File.exist?(source.bundled_path)

        storable_count(Source.parse(File.read(source.bundled_path)).domains)
      end

      def record(source, status, fetched_at, **attributes)
        SourceSnapshot.create!(source: source.name, url: source.url, status: status, fetched_at: fetched_at, **attributes)
      end

      def publish!(withdrawn: nil)
        snapshots = {}
        missing_primaries = []

        configured_sources.each do |source|
          snapshot = SourceSnapshot.last_good(source.name)
          if snapshot
            snapshots[source] = snapshot.domain_list
          elsif source.name == withdrawn
            log :warn, "#{source.name} has no good snapshot left after the rollback; building the list without it."
          elsif source.primary? && source.bundled_path
            log :warn, "#{source.name} has no good snapshot yet; using the list bundled with the gem in its place."
            snapshots[source] = Source.parse(File.read(source.bundled_path)).domains
          elsif source.primary?
            missing_primaries << source.name
          else
            log :warn, "#{source.name} has no good snapshot yet; building the list without it."
          end
        end

        if missing_primaries.any?
          log :error, "Not publishing: primary source(s) #{missing_primaries.join(', ')} have never been fetched successfully. " \
                      'Keeping the current list (seeding it from the bundled snapshot if it is empty).'
          seed!
          return false
        end

        if withdrawn && snapshots.keys.none?(&:primary?)
          log :warn, "No primary source has a good snapshot after rolling back #{withdrawn}; " \
                     'publishing the list bundled with the gem in its place.'
          snapshots[Sources::DISPOSABLE_EMAIL_DOMAINS.with(name: 'bundled-fallback')] = Source.parse(bundled_domains.join("\n")).domains
        end

        merged = SourceMerge.call(snapshots, threshold: Nondisposable.configuration.corroboration_threshold,
                                             lineage: configured_sources)
        log :info, "Merged #{snapshots.size} source(s): #{merged.primary_count} from primaries, #{merged.corroborated_count} corroborated."
        published = publish_domains(merged.domains)
        seed! unless published
        published
      end

      # ---- Single-source path (no snapshots table) ------------------------

      def update_single_source
        if sources_customised?
          log :warn, 'config.sources is customised but the nondisposable_source_snapshots table does not exist yet. ' \
                     'Only the default list is used until you run `rails g nondisposable:upgrade` and `rails db:migrate`.'
        end

        parsed = Source.parse(SourceFetcher.fetch(Sources::DISPOSABLE_EMAIL_DOMAINS))
        raise 'The list is empty. This might indicate a problem with the format.' if parsed.domains.empty?
        if parsed.invalid_ratio > Source::MAX_INVALID_RATIO
          raise "#{parsed.invalid} of #{parsed.lines} lines are not domain names (e.g. #{parsed.invalid_sample.map(&:inspect).join(', ')})"
        end

        log :info, 'Downloaded list of disposable domains...'
        published = with_publish_lock { publish_domains(parsed.domains) }
        raise 'Could not publish the list' unless published

        true
      end

      def sources_customised?
        Array(Nondisposable.configuration.sources).map { |source| Source.build(source) } != Sources::DEFAULT
      rescue ArgumentError
        true
      end

      # ---- Seeding and writing ----------------------------------------------

      def seed!
        return false unless DisposableDomain.none?

        log :info, 'Domain table is empty; seeding from the blocklist bundled with the gem...'
        domains = Source.parse(bundled_domains.join("\n")).domains
        return false unless publish_domains(domains)

        log :info, "Seeded #{DisposableDomain.count} disposable domains from the bundled snapshot. Run Nondisposable::DomainListUpdater.update to fetch the latest list."
        true
      end

      def bundled_domains
        File.readlines(BUNDLED_LIST_PATH, chomp: true)
      end

      # Applies the precedence table and writes the result. Callers hold the
      # publish lock.
      def publish_domains(domains)
        result = Precedence.filter(domains)
        log_dropped(result)

        if result.kept.empty?
          log :error, 'Refusing to publish an empty list of disposable domains. Keeping the current one.'
          return false
        end

        write_domains(result.kept | legacy_spellings(domains, result.kept))
        true
      end

      # The unicode spelling of every kept internationalised domain that
      # arrived in unicode, stored ALONGSIDE its canonical punycode row.
      #
      # Readers since 0.5.0 look up the punycode form (and match either row);
      # 0.4.0 looked up exactly what the user typed, lowercased. Storing both
      # keeps a mixed-version deploy, or a rollback to 0.4.0, from silently
      # unblocking `bücher.de`. Every upstream list already ships IDNs as
      # `xn--`, so in practice this only adds rows for host `additional_domains`
      # typed in unicode.
      def legacy_spellings(domains, kept)
        raw = domains.to_a + Array(Nondisposable.configuration.additional_domains)
        raw.each_with_object(Set.new) do |entry, spellings|
          next if entry.to_s.ascii_only?

          spelling = Domain.unicode(entry)
          next if spelling.ascii_only? || spelling.encoding == Encoding::BINARY

          spellings << spelling if kept.include?(Domain.normalize(entry))
        end
      end

      # Replaces the stored list with `domains` in one transaction, writing only
      # the difference: readers see the old list or the new one, never a gap.
      # Reports (instead of silently swallowing) any rows the bulk insert skipped.
      #
      # The current list is read INSIDE the transaction, so the diff is taken
      # against what this transaction will overwrite. On SQLite a concurrent
      # writer then makes this one fail (SQLITE_BUSY) instead of merging two
      # stale diffs; on PostgreSQL/MySQL the publish lock already serializes us.
      def write_domains(domains)
        current = added = removed = nil

        ActiveRecord::Base.transaction do
          current = DisposableDomain.pluck(:name).to_set
          added = (domains - current).to_a.sort
          removed = (current - domains).to_a.sort
          log :info, 'Updating disposable domains...'
          removed.each_slice(INSERT_BATCH_SIZE) { |batch| DisposableDomain.where(name: batch).delete_all }
          added.each_slice(INSERT_BATCH_SIZE) do |batch|
            DisposableDomain.insert_all(batch.map { |name| { name: name } }, record_timestamps: true)
          end
        end

        if added.any?
          stored = added.each_slice(INSERT_BATCH_SIZE).sum { |batch| DisposableDomain.where(name: batch).count }
          if stored < added.size
            skipped = added - added.each_slice(INSERT_BATCH_SIZE).flat_map { |batch| DisposableDomain.where(name: batch).pluck(:name) }
            log :warn, "Skipped #{added.size - stored} row(s) during bulk insert (duplicate or conflicting values): #{preview(skipped)}"
          end
        end

        total = DisposableDomain.count
        log :info, "Finished updating disposable domains. Total domains: #{total} (+#{added.size} -#{removed.size})."
        log :info, "Added: #{preview(added)}" if added.any? && current.any?
        log :info, "Removed: #{preview(removed)}" if removed.any?
        total
      end

      # ---- Locking ------------------------------------------------------------

      # Database-wide where the adapter has advisory locks (PostgreSQL, MySQL),
      # process-wide otherwise. SQLite needs no more: it allows one writer at a
      # time, and two processes publishing the same snapshots write the same
      # rows. Returns the block's value, or nil when another process held the
      # lock for longer than PUBLISH_LOCK_WAIT (it is publishing the same thing).
      def with_publish_lock(&block)
        PROCESS_LOCK.synchronize do
          DisposableDomain.connection_pool.with_connection do |connection|
            next block.call unless connection.supports_advisory_locks?

            acquired = false
            deadline = monotonic + PUBLISH_LOCK_WAIT
            until (acquired = connection.get_advisory_lock(PUBLISH_LOCK_ID))
              if monotonic > deadline
                log :warn, "Another process has been publishing for over #{PUBLISH_LOCK_WAIT}s; skipping this publish."
                break
              end
              sleep 0.25
            end
            next nil unless acquired

            begin
              block.call
            ensure
              connection.release_advisory_lock(PUBLISH_LOCK_ID)
            end
          end
        end
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # ---- Logging ------------------------------------------------------------

      def log_changes(source, previous, parsed)
        before = previous ? previous.domain_list.to_set : Set.new
        after = parsed.domains.to_set
        added = (after - before).to_a.sort
        removed = (before - after).to_a.sort
        message = "#{source.name}: #{after.size} domains (+#{added.size} -#{removed.size})"
        message += ", #{parsed.invalid} unparseable line(s) dropped" if parsed.invalid.positive?
        log :info, message
        return unless previous

        log :info, "#{source.name} added: #{preview(added)}" if added.any?
        log :info, "#{source.name} removed: #{preview(removed)}" if removed.any?
      end

      # A source listing a domain we KNOW is real is either an upstream false
      # positive or an attempt to poison the list. Either way it is dropped at
      # publish time, and it deserves a human's attention now.
      def log_poison(source, domains)
        never = Precedence.never_disposable
        poisoned = domains.select { |domain| Precedence.namespace_hit(domain, never) }
        suffixes = domains.select { |domain| PublicSuffix.public_suffix?(domain) }

        if poisoned.any?
          log :warn, "#{source.name} lists #{poisoned.size} domain(s) known to be real providers; they will NOT be blocked " \
                     "(upstream false positive or poisoning): #{preview(poisoned)}"
        end
        return if suffixes.empty?

        log :warn, "#{source.name} lists #{suffixes.size} public suffix(es); they will NOT be blocked: #{preview(suffixes)}"
      end

      def log_dropped(result)
        result.dropped_by_reason.each do |reason, domains|
          level = %i[additional_domain_is_never_disposable invalid_additional_domain].include?(reason) ? :warn : :info
          log level, "Not storing #{domains.size} domain(s) (#{reason}): #{preview(domains)}"
        end
      end

      def preview(domains)
        text = domains.first(LOG_PREVIEW).join(', ')
        text += ", … (#{domains.size - LOG_PREVIEW} more)" if domains.size > LOG_PREVIEW
        text
      end

      def log(level, message)
        Rails.logger.public_send(level, "[nondisposable] #{message}")
      end
    end
  end
end
