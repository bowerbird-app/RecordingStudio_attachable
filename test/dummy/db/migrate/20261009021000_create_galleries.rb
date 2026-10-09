# frozen_string_literal: true

class CreateGalleries < ActiveRecord::Migration[8.1]
  def change
    create_table :galleries, id: :uuid do |t|
      t.string :title, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
  end
end
