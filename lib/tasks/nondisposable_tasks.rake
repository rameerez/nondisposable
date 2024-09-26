# frozen_string_literal: true

require 'open-uri'
require 'net/http'

namespace :nondisposable do
  desc "Update the list of disposable email domains"
  task update_disposable_domains: :environment do
    Rails.logger.info "Refreshing list of disposable domains..."

    url = 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf'

    begin
      uri = URI(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        downloaded_domains = response.body.split("\n")
        raise "The list is empty. This might indicate a problem with the format." if downloaded_domains.empty?

        Rails.logger.info "Downloaded list of disposable domains..."

        domains = (downloaded_domains + Nondisposable.configuration.additional_domains).uniq
        domains -= Nondisposable.configuration.excluded_domains

        ActiveRecord::Base.transaction do
          Rails.logger.info "Updating disposable domains..."
          Nondisposable::DisposableDomain.delete_all

          domains.each { |domain| Nondisposable::DisposableDomain.create(name: domain.downcase) }
        end

        Rails.logger.info "Finished updating disposable domains. Total domains: #{domains.count}"
      else
        Rails.logger.error "Failed to download the list. HTTP Status: #{response.code}"
      end
    rescue SocketError => e
      Rails.logger.error "Network error occurred: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "An error occurred when trying to update the list of disposable domains: #{e.message}"
    end
  end
end
