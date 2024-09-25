# frozen_string_literal: true

module Nondisposable
  class EmailValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return if value.blank?

      domain = value.split('@').last.downcase
      if DisposableDomain.disposable?(domain)
        record.errors.add(attribute, options[:message] || Nondisposable.configuration.error_message)
      end
    end
  end
end

# Add this to ActiveModel::Validations
module ActiveModel
  module Validations
    module ClassMethods
      def validates_nondisposable_email_of(*attr_names)
        validates_with Nondisposable::EmailValidator, _merge_attributes(attr_names)
      end
    end
  end
end
