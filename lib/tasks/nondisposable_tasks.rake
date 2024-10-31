# frozen_string_literal: true

namespace :nondisposable do
  desc "Update the list of disposable email domains"
  task update_disposable_domains: :environment do
    Nondisposable::DomainListUpdater.update
  end
end
