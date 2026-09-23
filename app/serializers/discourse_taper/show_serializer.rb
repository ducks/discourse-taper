# frozen_string_literal: true

module DiscourseTaper
  class ShowSerializer < ApplicationSerializer
    attributes :id,
               :date,
               :sequence,
               :label,
               :title,
               :venue,
               :city,
               :region,
               :country,
               :location,
               :tour,
               :setlist,
               :notes,
               :url,
               :topic_id,
               :topic_url,
               :band,
               :sources

    def band
      {
        id: object.band.id,
        name: object.band.name,
        slug: object.band.slug,
        url: object.band.url,
        primary: object.band.primary?,
      }
    end

    def sources
      object.sources.order(:created_at).map { |s| SourceSerializer.new(s, root: false).as_json }
    end

    def topic_url
      object.topic&.relative_url
    end
  end
end
