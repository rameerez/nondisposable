# frozen_string_literal: true

module ActiveModel
  module Validations
    class NondisposableValidator < EachValidator
      def validate_each(record, attribute, value)
        return if value.blank?

        begin
          domain = value.to_s.split('@').last&.downcase
          return if domain.nil? # Invalid email format

          if Nondisposable::DisposableDomain.disposable?(domain)
            record.errors.add(attribute, options[:message] || Nondisposable.configuration.error_message)
          end
        rescue StandardError => e
          Rails.logger.error "Nondisposable validation error: #{e.message}"
          record.errors.add(attribute, "is an invalid email address, cannot check if it's disposable")
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
