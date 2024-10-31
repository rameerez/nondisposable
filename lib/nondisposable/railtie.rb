module Nondisposable
  class Railtie < Rails::Railtie
    initializer 'nondisposable.add_validator' do
      ActiveSupport.on_load(:active_record) do
        include ActiveModel::Validations::NondisposableValidator
      end
    end
  end
end
