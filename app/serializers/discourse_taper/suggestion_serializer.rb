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
               :source,
               :nearby_shows

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
      object.show &&
        {
          id: object.show.id,
          label: object.show.label,
          url: object.show.url,
          venue: object.show.venue,
          city: object.show.city,
        }
    end

    # For a proposed show: the band's known shows within a few days, so a
    # reviewer can spot a tape dated by its upload day, or a night setlist.fm
    # does not have yet.
    def nearby_shows
      return nil if object.kind != "new_show" || object.band.nil?
      date = ShowMatcher.safe_iso(object.payload["date"])
      return nil if date.nil?
      object
        .band
        .shows
        .where(date: (date - 3)..(date + 3))
        .order(:date)
        .map do |show|
          {
            label: show.label,
            venue: show.venue,
            city: show.city,
            url: show.url,
            days: (show.date - date).to_i,
          }
        end
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
