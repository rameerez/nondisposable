# frozen_string_literal: true

require 'net/http'
require 'uri'

module Nondisposable
  # Refreshes the vendored IANA TLD snapshot from the root zone database.
  #
  # ⚠️ This is a MAINTENANCE task, not a runtime one — the deliberate opposite of
  # DomainListUpdater. That one runs in your app, on a schedule, because
  # disposable domains change every few days and live in your database. This one
  # rewrites a file inside the gem, which is read-only once the gem is installed.
  # Run it in a checkout of the gem before cutting a release:
  #
  #   rake nondisposable:tlds:update
  #
  # If you need a TLD that is newer than your installed gem, do NOT reach for
  # this. Add it to `config.additional_tlds` and you are unblocked immediately,
  # with no release and no writable-gem-directory problem:
  #
  #   config.additional_tlds = %w[newtld]
  #
  # New TLDs are delegated in batches a few times a year, so a snapshot ages
  # slowly. ICANN's next application round is the first real test of that.
  class TldListUpdater
    LIST_URL = 'https://data.iana.org/TLD/tlds-alpha-by-domain.txt'

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 10

    # A root zone that suddenly contains a handful of entries means the fetch
    # went wrong (a captive portal, an error page, a truncated body), not that
    # ICANN deleted the internet. Refuse to overwrite a good list with junk.
    MINIMUM_PLAUSIBLE_TLD_COUNT = 1_000

    class << self
      # Returns the number of TLDs written, or nil if nothing was written.
      def update(path: Nondisposable::Tld::LIST_PATH)
        log :info, "Fetching the IANA root zone TLD list from #{LIST_URL}..."

        response = fetch
        unless response.is_a?(Net::HTTPSuccess)
          log :error, "Failed to download the TLD list. HTTP status: #{response.code}. Keeping the existing snapshot."
          return nil
        end

        body = response.body.to_s
        count = body.lines.count { |line| meaningful?(line) }

        if count < MINIMUM_PLAUSIBLE_TLD_COUNT
          log :error, "Refusing to write a TLD list with only #{count} entries (expected at least #{MINIMUM_PLAUSIBLE_TLD_COUNT}). Keeping the existing snapshot."
          return nil
        end

        # Written whole, then moved into place, so an interrupted run can never
        # leave a half-written root zone behind.
        tmp = "#{path}.tmp"
        File.write(tmp, body)
        File.rename(tmp, path)
        Nondisposable::Tld.reload!

        log :info, "Wrote #{count} TLDs to #{path} (#{Nondisposable::Tld.version})."
        count
      rescue StandardError => e
        log :error, "Could not update the TLD list: #{e.class}: #{e.message}. Keeping the existing snapshot."
        nil
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      private

      def meaningful?(line)
        value = line.to_s.strip
        !value.empty? && !value.start_with?('#')
      end

      def fetch
        uri = URI(LIST_URL)
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| http.get(uri.request_uri) }
      end

      # Usable from a bare `rake` run in a gem checkout, where there is no Rails
      # logger to talk to.
      def log(level, message)
        message = "[nondisposable] #{message}"
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.public_send(level, message)
        else
          warn message
        end
      end
    end
  end
end
