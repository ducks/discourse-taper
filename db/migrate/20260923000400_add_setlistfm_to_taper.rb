# frozen_string_literal: true

class AddSetlistfmToTaper < ActiveRecord::Migration[8.0]
  def change
    add_column :taper_shows, :setlistfm_id, :string
    add_index :taper_shows, :setlistfm_id, unique: true, where: "setlistfm_id IS NOT NULL"
    add_column :taper_bands, :setlistfm_artist_name, :string
  end
end
