# frozen_string_literal: true

require 'active_support/concern'
require 'active_model/type'

module Nondisposable
  # The way out of a lookalike error: "yes, this address is right".
  #
  # With `reject_lookalike_domains` on, `someone@ge.com` gets "looks like a
  # typo. Did you mean someone@me.com?" — and General Electric's staff are not
  # mistyping anything. Offline the gem cannot tell them from `gmial.com`, so
  # instead of refusing, it asks. This concern gives the record somewhere to
  # put the answer:
  #
  #   class User < ApplicationRecord
  #     include Nondisposable::ConfirmableEmail
  #     confirmable_email :email          # defines email_lookalike_confirmed
  #
  #     validates :email, nondisposable: true
  #   end
  #
  #   # In the form, only when that error is showing:
  #   <% if @user.errors.of_kind?(:email, :lookalike_domain) %>
  #     <%= f.check_box :email_lookalike_confirmed %>
  #     <%= f.label :email_lookalike_confirmed, "Sí, mi email es correcto" %>
  #   <% end %>
  #
  #   # And permit it: params.require(:user).permit(:email, :email_lookalike_confirmed)
  #
  # A confirmed record passes the lookalike check and nothing else: a
  # disposable provider, a TLD that does not exist, a blocked TLD and a
  # reviewed typo (Nondisposable::KnownTypos) are still refused, because for
  # those there is no address the user could be right about.
  #
  # The attribute is virtual — never persisted — and is reset after every
  # save, so it answers for one save: a later lookalike is asked again.
  #
  # No concern needed if you would rather wire it yourself: the validator
  # looks for a method named `<attribute>_lookalike_confirmed` returning true,
  # however the record defines it.
  module ConfirmableEmail
    extend ActiveSupport::Concern

    SUFFIX = '_lookalike_confirmed'

    class_methods do
      def confirmable_email(*attributes)
        attributes.each do |attribute|
          name = "#{attribute}#{SUFFIX}"
          ivar = "@#{name}"

          define_method(name) { instance_variable_defined?(ivar) ? instance_variable_get(ivar) : false }
          # Form params arrive as "1", "0", "true", "" — cast the way Rails
          # casts a boolean column, so a checkbox works without ceremony.
          define_method("#{name}=") { |value| instance_variable_set(ivar, ActiveModel::Type::Boolean.new.cast(value) || false) }
          alias_method "#{name}?", name
        end

        # Cleared after every save, so a record that was confirmed once and
        # then given a different lookalike address is asked again.
        return unless respond_to?(:after_save)

        names = attributes.map { |attribute| "#{attribute}#{SUFFIX}" }
        after_save { names.each { |name| public_send("#{name}=", false) } }
      end
    end

    # Has the user confirmed this attribute's address as typed? Strictly
    # `true`: a truthy string a host forgot to cast must not count as a "yes".
    def self.confirmed?(record, attribute)
      reader = "#{attribute}#{SUFFIX}"
      record.respond_to?(reader) && record.public_send(reader) == true
    end
  end
end
