# frozen_string_literal: true

module DiscourseTaper
  class Band < ActiveRecord::Base
    self.table_name = "taper_bands"

    has_many :shows,
             class_name: "DiscourseTaper::Show",
             foreign_key: :band_id,
             dependent: :restrict_with_error

    validates :name, presence: true, length: { maximum: 200 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

    before_validation :derive_slug

    def url
      "#{DiscourseTaper.root_path}/#{slug}"
    end

    private

    def derive_slug
      self.slug = name.to_s.parameterize if slug.blank? && name.present?
    end
  end
end
