# frozen_string_literal: true

module Nondisposable
  class DisposableDomain < ApplicationRecord
    validates :name, presence: true, uniqueness: { case_sensitive: false }

    class << self
      def disposable?(domain)
        return false if domain.blank?
        domain = domain.to_s.downcase
        Nondisposable.configuration.additional_domains.include?(domain) ||
          (where(name: domain).exists? && !Nondisposable.configuration.excluded_domains.include?(domain))
      end
    end

  end
end
