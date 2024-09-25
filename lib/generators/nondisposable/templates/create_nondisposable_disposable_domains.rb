class CreateNondisposableDisposableDomains < ActiveRecord::Migration[7.0]
  def change
    create_table :nondisposable_disposable_domains do |t|
      t.string :name, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
