module Nondisposable
  class Railtie < Rails::Railtie
    initializer 'nondisposable.add_validator' do
      ActiveSupport.on_load(:active_record) do
        include Nondisposable::Validations
      end
    end
  end
end
