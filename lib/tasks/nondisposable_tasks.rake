# frozen_string_literal: true

require 'open-uri'

namespace :nondisposable do
  desc "Update the list of disposable email domains"
  task update_disposable_domains: :environment do
    Rails.logger.info "Refreshing list of disposable domains..."

    url = 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf'
    # url = 'http://localhost:3002/disposable_email_blocklist.conf'

    begin
      downloaded_domains = URI.open(url).read.split("\n")
      raise "The list is empty. This might indicate a problem with the format." if downloaded_domains.empty?

      Rails.logger.info "Downloaded list of disposable domains..."

      domains = (downloaded_domains + Nondisposable.configuration.additional_domains).uniq
      domains -= Nondisposable.configuration.excluded_domains

      ActiveRecord::Base.transaction do
        Rails.logger.info "Updating disposable domains..."
        Nondisposable::DisposableDomain.delete_all

        domains.map { |domain| Nondisposable::DisposableDomain.create(name: domain.downcase) }
      end

      Rails.logger.info "Refreshing cache..."
      Nondisposable::DisposableDomain.refresh_cache

      Rails.logger.info "Finished updating disposable domains."
    rescue OpenURI::HTTPError => e
      Rails.logger.error "An error occurred when trying to download the list of disposable domains: #{e.message}"
    rescue => e
      Rails.logger.error "An error occurred when trying to update the list of disposable domains: #{e.message}"
    end
  end
end
