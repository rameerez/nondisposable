# frozen_string_literal: true

require 'open-uri'

namespace :nondisposable do
  desc "Update the list of disposable email domains"
  task update_disposable_domains: :environment do
    Rails.logger.info "Refreshing list of disposable domains..."

    url = 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf'

    begin
      downloaded_domains = URI.open(url).read.split("\n")
      raise "The list is empty. This might indicate a problem with the format." if downloaded_domains.empty?

      Rails.logger.info "Downloaded list of disposable domains..."

      ActiveRecord::Base.transaction do
        Rails.logger.info "Deleting all existing disposable domains to replace them with the new ones..."
        Nondisposable::DisposableDomain.delete_all

        Rails.logger.info "Importing all new disposable domains..."
        Nondisposable::DisposableDomain.import downloaded_domains.map { |name| { name: name } }, validate: false
      end

      Rails.logger.info "Finished importing new disposable domains."
    rescue OpenURI::HTTPError => e
      Rails.logger.error "An error occurred when trying to download the list of disposable domains: #{e.message}"
    rescue => e
      Rails.logger.error "An error occurred when trying to update the list of disposable domains: #{e.message}"
    end
  end
end
