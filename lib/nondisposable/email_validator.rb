# frozen_string_literal: true

module ActiveModel
  module Validations
    class NondisposableValidator < EachValidator
      def validate_each(record, attribute, value)
        return if value.blank?

        domain = value.split('@').last.downcase
        if Nondisposable::DisposableDomain.disposable?(domain)
          record.errors.add(attribute, options[:message] || Nondisposable.configuration.error_message)
        end
      end
    end

    module HelperMethods
      # Kept for backwards compatibility
      def validates_nondisposable_email(*attr_names)
        validates_with NondisposableValidator, _merge_attributes(attr_names)
      end
    end
  end
end
