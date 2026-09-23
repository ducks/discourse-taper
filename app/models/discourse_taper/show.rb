# frozen_string_literal: true

module DiscourseTaper
  # One performance: a band on a date at a venue. Recordings, videos, and
  # archive items are Sources attached to it. The topic is the show's
  # discussion and permission boundary.
  class Show < ActiveRecord::Base
    self.table_name = "taper_shows"

    belongs_to :band, class_name: "DiscourseTaper::Band"
    belongs_to :topic
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :venue_record,
               class_name: "DiscourseTaper::Venue",
               foreign_key: :venue_id,
               optional: true
    has_many :sources,
             class_name: "DiscourseTaper::Source",
             foreign_key: :show_id,
             dependent: :destroy
    has_many :suggestions, class_name: "DiscourseTaper::Suggestion", foreign_key: :show_id

    validates :date, presence: true
    validates :venue, presence: true, length: { maximum: 200 }
    validates :sequence, numericality: { greater_than: 0 }
    validates :topic_id, uniqueness: true
    validates :sequence, uniqueness: { scope: %i[band_id date] }
    validate :setlist_shape

    scope :by_date, -> { order(date: :desc, sequence: :desc) }
    scope :for_year, ->(year) { where(date: Date.new(year, 1, 1)..Date.new(year, 12, 31)) }

    # "1977-05-08" or "1977-05-08 (late show)" once there is a second show.
    def label
      base = date.iso8601
      base = "#{base} (#{I18n.t("taper.show.sequence", n: sequence)})" if sequence > 1
      base
    end

    # "1977-05-08 Barton Hall, Ithaca" for the primary band; other bands
    # keep their name so a side project is identifiable in topic lists.
    def title
      [band.primary? ? nil : band.name, label, [venue, city].compact.join(", ")].compact.join(" ")
    end

    def location
      [venue, city, region, country].compact.join(", ")
    end

    def url
      "#{DiscourseTaper.root_path}#{band.path_prefix}/#{slug}"
    end

    def slug
      "#{date.iso8601}#{sequence > 1 ? "-#{sequence}" : ""}"
    end

    def setlist_titles
      setlist.map { |song| song["title"] }.compact
    end

    private

    def setlist_shape
      return if setlist.is_a?(Array) && setlist.all? { |s| s.is_a?(Hash) && s["title"].present? }
      errors.add(:setlist, :invalid)
    end
  end
end

# == Schema Information
#
# Table name: taper_shows
#
#  id            :bigint           not null, primary key
#  city          :string
#  country       :string
#  date          :date             not null
#  notes         :text
#  region        :string
#  sequence      :integer          default(1), not null
#  setlist       :jsonb            not null
#  tour          :string
#  venue         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  band_id       :bigint           not null
#  created_by_id :bigint
#  setlistfm_id  :string
#  topic_id      :bigint           not null
#  venue_id      :bigint
#
# Indexes
#
#  index_taper_shows_on_band_id_and_date               (band_id,date)
#  index_taper_shows_on_band_id_and_date_and_sequence  (band_id,date,sequence) UNIQUE
#  index_taper_shows_on_setlistfm_id                   (setlistfm_id) UNIQUE WHERE (setlistfm_id IS NOT NULL)
#  index_taper_shows_on_topic_id                       (topic_id) UNIQUE
#  index_taper_shows_on_venue_id                       (venue_id)
#
