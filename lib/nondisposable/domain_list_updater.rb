# frozen_string_literal: true

require 'net/http'
require 'uri'

module Nondisposable
  class DomainListUpdater

    LIST_URL = 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf'

    # Network timeouts (seconds). Without these, a hung connection would block
    # the calling job/thread indefinitely (Net::HTTP defaults to 60s open / 60s read).
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 10

    def self.update
      Rails.logger.info "[nondisposable] Refreshing list of disposable domains..."

      begin
        response = fetch_list

        if response.is_a?(Net::HTTPSuccess)
          downloaded_domains = response.body.split("\n")
          raise "The list is empty. This might indicate a problem with the format." if downloaded_domains.empty?

          Rails.logger.info "[nondisposable] Downloaded list of disposable domains..."

          replace_domains(downloaded_domains)
          true
        else
          Rails.logger.error "[nondisposable] Failed to download the list. HTTP Status: #{response.code}"
          false
        end
      rescue SocketError => e
        Rails.logger.error "[nondisposable] Network error occurred: #{e.message}"
        false
      rescue StandardError => e
        Rails.logger.error "[nondisposable] An error occurred when trying to update the list of disposable domains: #{e.message}"
        false
      end
    end

    def self.fetch_list
      uri = URI(LIST_URL)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) do |http|
        http.get(uri.request_uri)
      end
    end
    private_class_method :fetch_list

    # Atomically replaces the stored domain list with the given raw list,
    # merged with `additional_domains` and minus `excluded_domains`.
    # Reports (instead of silently swallowing) any rows the bulk insert skipped.
    def self.replace_domains(raw_domains)
      domains = normalize(raw_domains + Nondisposable.configuration.additional_domains)
      domains -= normalize(Nondisposable.configuration.excluded_domains)

      inserted_count = 0

      ActiveRecord::Base.transaction do
        Rails.logger.info "[nondisposable] Updating disposable domains..."
        Nondisposable::DisposableDomain.delete_all

        records = domains.map { |domain| { name: domain } }
        Nondisposable::DisposableDomain.insert_all(records, record_timestamps: true) if records.any?
        inserted_count = Nondisposable::DisposableDomain.count
      end

      skipped_count = domains.size - inserted_count
      if skipped_count.positive?
        skipped = domains - Nondisposable::DisposableDomain.where(name: domains).pluck(:name)
        preview = skipped.take(20).join(', ')
        preview += ", … (#{skipped.size - 20} more)" if skipped.size > 20
        Rails.logger.warn "[nondisposable] Skipped #{skipped_count} row(s) during bulk insert (duplicate or conflicting values): #{preview}"
      end

      Rails.logger.info "[nondisposable] Finished updating disposable domains. Total domains: #{inserted_count}"
      inserted_count
    end
    private_class_method :replace_domains

    # Downcases, strips whitespace (including stray \r from CRLF payloads),
    # drops blank lines, and dedupes.
    def self.normalize(domains)
      domains.map { |domain| domain.to_s.strip.downcase }.reject(&:empty?).uniq
    end
    private_class_method :normalize
  end
end
