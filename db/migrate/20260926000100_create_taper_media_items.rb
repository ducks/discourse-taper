# frozen_string_literal: true

class CreateTaperMediaItems < ActiveRecord::Migration[8.0]
  def change
    create_table :taper_media_items do |t|
      t.bigint :band_id, null: false
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :url, null: false
      t.string :title, null: false
      t.string :kind, null: false, default: "misc"
      t.string :channel
      t.date :published_on
      t.integer :duration_seconds
      t.string :reason
      t.boolean :hidden, null: false, default: false
      t.timestamps
    end

    add_index :taper_media_items, %i[provider external_id], unique: true
    add_index :taper_media_items, %i[band_id kind published_on]
  end
end
