# frozen_string_literal: true

class CreateTaperTables < ActiveRecord::Migration[8.0]
  def change
    create_table :taper_bands do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      # Identifiers on external services, used by the importers to scope
      # their searches and to match results back to this band.
      t.string :archive_org_collection
      t.string :youtube_channel_id
      t.timestamps
    end
    add_index :taper_bands, :slug, unique: true

    create_table :taper_shows do |t|
      t.integer :band_id, null: false
      t.integer :topic_id, null: false
      t.date :date, null: false
      # Ordinal for two shows on one date (early and late show).
      t.integer :sequence, null: false, default: 1
      t.string :venue, null: false
      t.string :city
      t.string :region
      t.string :country
      t.string :tour
      # Ordered setlist: [{ "title" => "...", "notes" => "...", "set" => "1" }, ...]
      t.jsonb :setlist, null: false, default: []
      t.text :notes
      t.integer :created_by_id
      t.timestamps
    end
    add_index :taper_shows, :topic_id, unique: true
    add_index :taper_shows, %i[band_id date sequence], unique: true
    add_index :taper_shows, %i[band_id date]

    create_table :taper_sources do |t|
      t.integer :show_id, null: false
      # audience | soundboard | matrix | video | unknown
      t.string :kind, null: false, default: "unknown"
      # flac | mp3 | shn | video | stream | unknown
      t.string :format, null: false, default: "unknown"
      # archive_org | youtube | upload | link
      t.string :provider, null: false
      # The provider's own id (archive.org identifier, YouTube video id) so
      # an importer never attaches the same item twice.
      t.string :external_id
      t.string :url
      t.integer :upload_id
      t.string :title
      t.integer :taper_id
      t.string :taper_name
      t.text :lineage
      t.integer :duration_seconds
      t.integer :submitted_by_id
      t.timestamps
    end
    add_index :taper_sources, :show_id
    add_index :taper_sources,
              %i[provider external_id],
              unique: true,
              where: "external_id IS NOT NULL"

    create_table :taper_suggestions do |t|
      # new_show | new_source | correction
      t.string :kind, null: false
      # pending | accepted | rejected
      t.string :status, null: false, default: "pending"
      t.integer :band_id
      t.integer :show_id
      # Everything proposed, shaped by kind. Kept as submitted so a reviewer
      # sees exactly what was offered and acceptance is reproducible.
      t.jsonb :payload, null: false, default: {}
      # Who or what proposed it: a user id, or nil for an importer, with the
      # importer named in origin.
      t.integer :submitted_by_id
      t.string :origin, null: false, default: "user"
      t.text :note
      t.integer :reviewed_by_id
      t.datetime :reviewed_at
      t.text :review_note
      t.timestamps
    end
    add_index :taper_suggestions, %i[status created_at]
    add_index :taper_suggestions, :show_id
    # An importer proposing the same external item twice is a no-op.
    add_index :taper_suggestions,
              %i[origin kind band_id],
              name: "index_taper_suggestions_on_origin_kind_band"
    add_index :taper_suggestions,
              "origin, (payload->>'external_id')",
              unique: true,
              where: "payload->>'external_id' IS NOT NULL AND status = 'pending'",
              name: "index_taper_suggestions_pending_external"
  end
end
