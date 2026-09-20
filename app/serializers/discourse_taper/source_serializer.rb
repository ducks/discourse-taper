# frozen_string_literal: true

module DiscourseTaper
  class SourceSerializer < ApplicationSerializer
    attributes :id,
               :kind,
               :format,
               :provider,
               :external_id,
               :url,
               :title,
               :taper,
               :lineage,
               :duration_seconds,
               :created_at

    def url
      object.display_url
    end

    def taper
      object.credited_taper
    end
  end
end
