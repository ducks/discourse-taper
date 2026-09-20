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
        errors.add(:payload, :invalid) if payload["url"].blank? && payload["upload_id"].blank?
        errors.add(:payload, :invalid) if show_id.nil? && (band_id.nil? || payload["date"].blank?)
      when "correction"
        errors.add(:payload, :invalid) if show_id.nil? || payload["changes"].blank?
      end
    end
  end
end
