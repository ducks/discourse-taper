# frozen_string_literal: true

module DiscourseTaper
  # The manual channel and the importers' inbox. Nothing an importer finds
  # becomes a record directly; it lands here for a person to accept.
  class Suggestion < ActiveRecord::Base
    self.table_name = "taper_suggestions"

    KINDS = %w[new_show new_source correction].freeze
    STATUSES = %w[pending accepted rejected].freeze

    belongs_to :band, class_name: "DiscourseTaper::Band", optional: true
    belongs_to :show, class_name: "DiscourseTaper::Show", optional: true
    belongs_to :submitted_by, class_name: "User", optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true

    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :origin, presence: true
    validate :payload_for_kind

    scope :pending, -> { where(status: "pending").order(created_at: :asc) }

    def pending?
      status == "pending"
    end

    def from_importer?
      origin != "user"
    end

    def external_id
      payload["external_id"]
    end

    private

    def payload_for_kind
      return errors.add(:payload, :invalid) if !payload.is_a?(Hash)

      case kind
      when "new_show"
        if band_id.nil? || payload["date"].blank? || payload["venue"].blank?
          errors.add(:payload, :invalid)
        end
      when "new_source"
        has_sources = payload["sources"].is_a?(Array) && payload["sources"].any?
        if !has_sources && payload["url"].blank? && payload["upload_id"].blank?
          errors.add(:payload, :invalid)
        end
        errors.add(:payload, :invalid) if show_id.nil? && (band_id.nil? || payload["date"].blank?)
      when "correction"
        errors.add(:payload, :invalid) if show_id.nil? || payload["changes"].blank?
      end
    end
  end
end

# == Schema Information
#
# Table name: taper_suggestions
#
#  id              :bigint           not null, primary key
#  kind            :string           not null
#  note            :text
#  origin          :string           default("user"), not null
#  payload         :jsonb            not null
#  review_note     :text
#  reviewed_at     :datetime
#  status          :string           default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  band_id         :bigint
#  reviewed_by_id  :bigint
#  show_id         :bigint
#  submitted_by_id :bigint
#
# Indexes
#
#  index_taper_suggestions_on_origin_kind_band       (origin,kind,band_id)
#  index_taper_suggestions_on_show_id                (show_id)
#  index_taper_suggestions_on_status_and_created_at  (status,created_at)
#  index_taper_suggestions_pending_external          (origin, ((payload ->> 'external_id'::text))) UNIQUE WHERE (((payload ->> 'external_id'::text) IS NOT NULL) AND ((status)::text = 'pending'::text))
#
