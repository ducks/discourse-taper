# frozen_string_literal: true

# Venues get their own table so a spelling only ever has to be resolved
# once. Every spelling an importer sees for an accepted show is learned as
# an alias, and pg_trgm (in core since 2013) catches typos and near misses.
class CreateTaperVenues < ActiveRecord::Migration[8.0]
  def up
    create_table :taper_venues do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :city
      t.string :region
      t.string :country
      # Normalised spellings that resolve to this venue.
      t.jsonb :aliases, null: false, default: []
      t.timestamps
    end
    add_index :taper_venues, :slug, unique: true
    add_index :taper_venues, :aliases, using: :gin
    execute "CREATE INDEX index_taper_venues_on_name_trgm ON taper_venues USING gin (name gin_trgm_ops)"

    add_column :taper_shows, :venue_id, :bigint
    add_index :taper_shows, :venue_id
  end

  def down
    remove_index :taper_shows, :venue_id
    remove_column :taper_shows, :venue_id
    drop_table :taper_venues
  end
end
