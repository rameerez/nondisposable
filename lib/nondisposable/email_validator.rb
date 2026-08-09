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
          if Nondisposable.configuration.on_check_failure == :reject
            Rails.logger.error "[nondisposable] Nondisposable validation error: #{e.message} — rejecting #{attribute} (on_check_failure = :reject)"
            record.errors.add(attribute, "is an invalid email address, cannot check if it's disposable")
          else
            Rails.logger.error "[nondisposable] Nondisposable validation error: #{e.message} — ALLOWING #{attribute} through without a disposable check (on_check_failure = :allow). Set config.on_check_failure = :reject to fail closed instead."
          end
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
