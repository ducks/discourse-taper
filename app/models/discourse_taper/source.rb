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

# == Schema Information
#
# Table name: taper_sources
#
#  id               :bigint           not null, primary key
#  duration_seconds :integer
#  format           :string           default("unknown"), not null
#  kind             :string           default("unknown"), not null
#  lineage          :text
#  provider         :string           not null
#  taper_name       :string
#  title            :string
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  external_id      :string
#  show_id          :bigint           not null
#  submitted_by_id  :bigint
#  taper_id         :bigint
#  upload_id        :bigint
#
# Indexes
#
#  index_taper_sources_on_provider_and_external_id  (provider,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#  index_taper_sources_on_show_id                   (show_id)
#
