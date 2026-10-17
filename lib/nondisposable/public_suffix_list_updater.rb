# frozen_string_literal: true

require 'net/http'
require 'uri'

module Nondisposable
  # Refreshes the vendored Public Suffix List snapshot.
  #
  # ⚠️ A MAINTENANCE task, like TldListUpdater: it rewrites a file inside the
  # gem, so run it in a checkout before cutting a release:
  #
  #   rake nondisposable:psl:update
  #
  # Host apps never need it. A stale PSL can only be LESS protective (a suffix
  # created after the snapshot is not known to be one), never lock anyone out.
  class PublicSuffixListUpdater
    # The PSL maintainers ask to be fetched from here and only here.
    LIST_URL = 'https://publicsuffix.org/list/public_suffix_list.dat'

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 10

    # The list holds ~10,000 rules. A body with a fraction of that is an error
    # page or a truncated download, not the internet shrinking.
    MINIMUM_PLAUSIBLE_RULE_COUNT = 5_000

    class << self
      # Returns the number of rules written, or nil if nothing was written.
      def update(path: Nondisposable::PublicSuffix::LIST_PATH)
        log :info, "Fetching the Public Suffix List from #{LIST_URL}..."

        response = fetch
        unless response.is_a?(Net::HTTPSuccess)
          log :error, "Failed to download the Public Suffix List. HTTP status: #{response.code}. Keeping the existing snapshot."
          return nil
        end

        body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
        rules = Nondisposable::PublicSuffix.parse(body)
        count = rules.values.sum(&:size)

        unless body.include?('===BEGIN ICANN DOMAINS===') && count >= MINIMUM_PLAUSIBLE_RULE_COUNT
          log :error, "Refusing to write a Public Suffix List with only #{count} rules (expected at least #{MINIMUM_PLAUSIBLE_RULE_COUNT} and an ICANN section). Keeping the existing snapshot."
          return nil
        end

        # Written whole, then moved into place, so an interrupted run can never
        # leave half a list behind.
        tmp = "#{path}.tmp"
        File.write(tmp, body)
        File.rename(tmp, path)
        Nondisposable::PublicSuffix.reload!

        log :info, "Wrote #{count} rules to #{path} (#{Nondisposable::PublicSuffix.version})."
        count
      rescue StandardError => e
        log :error, "Could not update the Public Suffix List: #{e.class}: #{e.message}. Keeping the existing snapshot."
        nil
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      private

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
