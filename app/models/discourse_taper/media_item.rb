# frozen_string_literal: true

module DiscourseTaper
  # The band's own output and its press: albums, singles, official
  # videos, promo, interviews, podcast appearances. Not shows, so no
  # topic and no review; the importers file these straight from what the
  # release detector flags, and a reviewer can hide one.
  class MediaItem < ActiveRecord::Base
    self.table_name = "taper_media_items"

    KINDS = %w[album single video promo interview podcast misc].freeze

    # Detector reasons to shelf kinds.
    KIND_FOR_REASON = {
      "album" => "album",
      "single" => "single",
      "official video" => "video",
      "music video" => "video",
      "teaser" => "promo",
      "interview" => "interview",
      "podcast" => "podcast",
    }.freeze

    belongs_to :band, class_name: "DiscourseTaper::Band"

    validates :provider, :external_id, :url, :title, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :external_id, uniqueness: { scope: :provider }

    scope :visible, -> { where(hidden: false) }
    scope :newest, -> { order(Arel.sql("published_on DESC NULLS LAST"), created_at: :desc) }

    def self.kind_for(reason)
      KIND_FOR_REASON.fetch(reason.to_s, "misc")
    end

    # Upsert by provider and id; a re-run refreshes what changed and never
    # un-hides what a reviewer hid.
    def self.file!(band:, provider:, external_id:, attributes:)
      item = find_or_initialize_by(provider: provider, external_id: external_id)
      item.band = band
      item.assign_attributes(attributes)
      item.save!
      item
    end
  end
end

# == Schema Information
#
# Table name: taper_media_items
#
#  id               :bigint           not null, primary key
#  channel          :string
#  duration_seconds :integer
#  hidden           :boolean          default(FALSE), not null
#  kind             :string           default("misc"), not null
#  provider         :string           not null
#  published_on     :date
#  reason           :string
#  title            :string           not null
#  url              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  band_id          :bigint           not null
#  external_id      :string           not null
#
# Indexes
#
#  index_taper_media_items_on_band_id_and_kind_and_published_on  (band_id,kind,published_on)
#  index_taper_media_items_on_provider_and_external_id           (provider,external_id) UNIQUE
#
