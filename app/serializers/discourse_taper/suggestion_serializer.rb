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
               :reviewed_by

    def band
      object.band && { id: object.band.id, name: object.band.name, slug: object.band.slug }
    end

    def show
      object.show && { id: object.show.id, label: object.show.label, url: object.show.url }
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
