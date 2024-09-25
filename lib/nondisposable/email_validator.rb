
# frozen_string_literal: true

module Nondisposable
  class EmailValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return if value.blank?

      domain = value.split('@').last
      if DisposableDomain.exists?(name: domain)
        record.errors.add(attribute, Nondisposable.configuration.error_message)
      end
    end
  end
end
