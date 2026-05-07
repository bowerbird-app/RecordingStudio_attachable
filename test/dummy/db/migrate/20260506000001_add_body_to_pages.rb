class AddBodyToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :body, :text
  end
end
