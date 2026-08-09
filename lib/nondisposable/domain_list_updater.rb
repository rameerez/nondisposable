# frozen_string_literal: true

require 'open-uri'
require 'net/http'

module Nondisposable
  class DomainListUpdater

    def self.update
      Rails.logger.info "[nondisposable] Refreshing list of disposable domains..."

      url = 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf'

      begin
        uri = URI(url)
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          downloaded_domains = response.body.split("\n")
          raise "The list is empty. This might indicate a problem with the format." if downloaded_domains.empty?

          Rails.logger.info "[nondisposable] Downloaded list of disposable domains..."

          domains = (downloaded_domains + Nondisposable.configuration.additional_domains).uniq
          domains -= Nondisposable.configuration.excluded_domains

          ActiveRecord::Base.transaction do
            Rails.logger.info "[nondisposable] Updating disposable domains..."
            Nondisposable::DisposableDomain.delete_all

            records = domains.map { |domain| { name: domain.downcase } }
            Nondisposable::DisposableDomain.insert_all(records, record_timestamps: true) if records.any?
          end

          Rails.logger.info "[nondisposable] Finished updating disposable domains. Total domains: #{domains.count}"
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
  end
end
