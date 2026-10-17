# frozen_string_literal: true

module Nondisposable
  # What one source said on one fetch — or why we refused to listen.
  #
  # The merged nondisposable_disposable_domains table cannot answer "which
  # list put this domain here?", and it cannot be rebuilt when one source has a
  # bad day: a single domain may come from several sources, and a domain one
  # corroborating source lists must survive until a second one agrees. So each
  # source keeps its own recent history here, and the merged table is always
  # REBUILT from each source's last good snapshot (DomainListUpdater.publish).
  #
  # Statuses:
  #   ok          accepted; `domains` holds the canonical list, one per line
  #   rejected    downloaded, but failed a guard (too small, shrank or grew
  #               implausibly, mostly junk); `error` says which
  #   failed      the download itself failed; `error` says how
  #   rolled_back an ok snapshot a human withdrew (DomainListUpdater.rollback)
  #
  # Only `ok` snapshots ever feed the published list. The table is optional:
  # without it (hosts that have not run `rails g nondisposable:upgrade`), the
  # updater keeps the single-source behaviour of 0.5 and earlier.
  class SourceSnapshot < ApplicationRecord
    self.table_name = 'nondisposable_source_snapshots'

    STATUSES = %w[ok rejected failed rolled_back].freeze

    # Rows kept per source: the newest RETAINED_PER_SOURCE of any status, plus
    # the newest RETAINED_OK_PER_SOURCE good ones however old (failures must
    # never evict the fallback, nor the shrink guard's baseline), plus EVERY
    # rolled-back row (its sha256 is what refuses the same poison next time).
    RETAINED_PER_SOURCE = 5
    RETAINED_OK_PER_SOURCE = 3

    validates :source, :status, :fetched_at, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :ok, -> { where(status: 'ok') }
    scope :newest_first, -> { order(fetched_at: :desc, id: :desc) }

    class << self
      # Is the table there? Checked on every update rather than memoized, so a
      # long-running process notices the upgrade migration without a restart.
      def available?
        connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
      rescue StandardError
        false
      end

      def last_good(source_name)
        ok.where(source: source_name).newest_first.first
      end

      def prune(source_name)
        rows = where(source: source_name)
        keep = rows.newest_first.limit(RETAINED_PER_SOURCE).pluck(:id) +
               rows.ok.newest_first.limit(RETAINED_OK_PER_SOURCE).pluck(:id)
        rows.where.not(id: keep).where.not(status: 'rolled_back').delete_all
      end
    end

    def domain_list
      domains.to_s.split("\n")
    end
  end
end
