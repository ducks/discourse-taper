# frozen_string_literal: true

module DiscourseTaper
  # One recording, video, or archive item of a show.
  class Source < ActiveRecord::Base
    self.table_name = "taper_sources"

    KINDS = %w[audience soundboard matrix video unknown].freeze
    FORMATS = %w[flac mp3 shn video stream unknown].freeze
    PROVIDERS = %w[archive_org youtube upload link].freeze

    belongs_to :show, class_name: "DiscourseTaper::Show"
    belongs_to :taper, class_name: "User", optional: true
    belongs_to :upload, optional: true
    belongs_to :submitted_by, class_name: "User", optional: true

    validates :kind, inclusion: { in: KINDS }
    validates :format, inclusion: { in: FORMATS }
    validates :provider, inclusion: { in: PROVIDERS }
    validates :external_id, uniqueness: { scope: :provider }, allow_nil: true
    validates :url, length: { maximum: 2000 }, allow_nil: true
    validate :has_a_location

    def display_url
      return upload.url if upload
      url
    end

    def credited_taper
      taper&.username || taper_name
    end

    private

    def has_a_location
      if url.blank? && upload_id.nil?
        errors.add(:base, I18n.t("taper.errors.source_needs_location"))
      end
    end
  end
end
