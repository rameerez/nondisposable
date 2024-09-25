# frozen_string_literal: true

module Nondisposable
  class DisposableDomain < ApplicationRecord
    validates :name, presence: true, uniqueness: { case_sensitive: false }

    class << self
      def disposable?(domain)
        Nondisposable.configuration.additional_domains.any? { |d| domain == d.downcase } ||
        (exists?(name: domain.downcase) && !Nondisposable.configuration.excluded_domains.any?{ |d| domain == d.downcase })
      end
    end

  end
end
