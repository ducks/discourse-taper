# frozen_string_literal: true

module DiscourseTaper
  class SuggestionSerializer < ApplicationSerializer
    attributes :id,
               :kind,
               :status,
               :origin,
               :payload,
               :note,
               :review_note,
               :created_at,
               :reviewed_at,
               :band,
               :show,
               :submitted_by,
               :reviewed_by,
               :source

    def band
      object.band &&
        {
          id: object.band.id,
          name: object.band.name,
          slug: object.band.slug,
          primary: object.band.primary?,
        }
    end

    def show
      object.show && { id: object.show.id, label: object.show.label, url: object.show.url }
    end

    # The recording a claim is about, so the queue can show and link it.
    def source
      return nil if object.kind != "claim" || object.show.nil?
      source = object.show.sources.find_by(id: object.payload["source_id"])
      source &&
        {
          id: source.id,
          title: source.title,
          url: source.display_url,
          provider: source.provider,
          kind: source.kind,
          taper_name: source.taper_name,
        }
    end

    def submitted_by
      user_json(object.submitted_by)
    end

    def reviewed_by
      user_json(object.reviewed_by)
    end

    private

    def user_json(user)
      user && { id: user.id, username: user.username, avatar_template: user.avatar_template }
    end
  end
end
