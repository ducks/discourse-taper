# frozen_string_literal: true

module DiscourseTaper
  # A site is usually "the X archive" with side projects alongside. The
  # primary band is the one the site is about: it drops out of URLs, show
  # titles, and the card, so a single-band site never sees the concept.
  class Band < ActiveRecord::Base
    self.table_name = "taper_bands"

    has_many :shows,
             class_name: "DiscourseTaper::Show",
             foreign_key: :band_id,
             dependent: :restrict_with_error

    validates :name, presence: true, length: { maximum: 200 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
    validates :primary, uniqueness: true, if: :primary?

    before_validation :derive_slug
    before_create :become_primary_if_first

    scope :primary, -> { where(primary: true) }

    def self.primary_band
      primary.first
    end

    def url
      primary? ? DiscourseTaper.root_path : "#{DiscourseTaper.root_path}/#{slug}"
    end

    # Segment shows use in their URL: nothing for the primary band.
    def path_prefix
      primary? ? "" : "/#{slug}"
    end

    def make_primary!
      Band.transaction do
        Band.primary.where.not(id: id).update_all(primary: false)
        update!(primary: true)
      end
    end

    private

    def derive_slug
      self.slug = name.to_s.parameterize if slug.blank? && name.present?
    end

    def become_primary_if_first
      self.primary = true if !Band.exists?
    end
  end
end

# == Schema Information
#
# Table name: taper_bands
#
#  id                     :bigint           not null, primary key
#  archive_org_collection :string
#  description            :text
#  name                   :string           not null
#  primary                :boolean          default(FALSE), not null
#  setlistfm_artist_name  :string
#  slug                   :string           not null
#  youtube_search_query   :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  youtube_channel_id     :string
#
# Indexes
#
#  index_taper_bands_on_primary  (primary) UNIQUE WHERE "primary"
#  index_taper_bands_on_slug     (slug) UNIQUE
#
