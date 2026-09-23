# frozen_string_literal: true

module DiscourseTaper
  # Turns an accepted suggestion into records. Rejection just records who
  # said no and why, so an importer will not re-propose the same item.
  # accept! always returns the show the suggestion ended up on.
  class SuggestionReviewer
    def initialize(reviewer:)
      @reviewer = reviewer
    end

    def accept!(suggestion, note: nil)
      raise Error.new("not_pending") if !suggestion.pending?

      Suggestion.transaction do
        show =
          case suggestion.kind
          when "new_show"
            create_show(suggestion)
          when "new_source"
            add_sources(suggestion)
          when "correction"
            apply_correction(suggestion)
          end
        suggestion.update!(
          status: "accepted",
          show: show,
          reviewed_by: @reviewer,
          reviewed_at: Time.zone.now,
          review_note: note,
        )
        show
      end
    end

    def reject!(suggestion, note: nil)
      raise Error.new("not_pending") if !suggestion.pending?
      suggestion.update!(
        status: "rejected",
        reviewed_by: @reviewer,
        reviewed_at: Time.zone.now,
        review_note: note,
      )
      suggestion
    end

    private

    def create_show(suggestion)
      p = suggestion.payload
      show =
        ShowCreator.new(user: suggestion.submitted_by || @reviewer).create!(
          band: suggestion.band,
          date: Date.parse(p["date"]),
          venue: p["venue"],
          city: p["city"],
          region: p["region"],
          country: p["country"],
          tour: p["tour"],
          setlist: Array(p["setlist"]),
          notes: p["notes"],
        )
      show.update!(setlistfm_id: p["setlistfm_id"]) if p["setlistfm_id"].present?
      link_venue!(
        show,
        p["venue"],
        city: p["city"],
        region: p["region"],
        country: p["country"],
        spellings: (p["venue_spellings"] || {}).keys,
      )
      sources_in(suggestion).each { |attrs| attach_source(show, attrs, suggestion) }
      show
    end

    # Every spelling seen for an accepted show becomes an alias, so the
    # reviewer answers the venue question once per venue.
    def link_venue!(show, name, city: nil, region: nil, country: nil, spellings: [])
      return if name.blank?
      venue =
        Venue.find_or_create_canonical!(name: name, city: city, region: region, country: country)
      venue.learn!([name, *spellings])
      show.update!(venue_id: venue.id, venue: venue.name)
    end

    def add_sources(suggestion)
      show = suggestion.show
      if show.nil?
        show =
          ShowMatcher.new(band: suggestion.band).find(
            date: Date.parse(suggestion.payload["date"]),
            venue: suggestion.payload["venue"],
          )
        raise Error.new("show_not_found") if show.nil?
      end
      sources_in(suggestion).each { |attrs| attach_source(show, attrs, suggestion) }
      show
    end

    # A suggestion carries recordings in one of three shapes: an importer's
    # `sources` array, the missing-show form's single `source`, or the
    # recording form's fields at the top level of the payload.
    def sources_in(suggestion)
      p = suggestion.payload
      return p["sources"] if p["sources"].is_a?(Array) && p["sources"].any?
      return [p["source"]] if p["source"].is_a?(Hash) && p["source"]["url"].present?
      return [p] if p["url"].present? || p["upload_id"].present?
      []
    end

    def attach_source(show, attrs, suggestion)
      # An importer may have appended a recording that a reviewer attached
      # by hand in the meantime; never attach the same external id twice.
      if attrs["external_id"].present? &&
           Source.exists?(provider: attrs["provider"], external_id: attrs["external_id"])
        return
      end

      Source.create!(
        show: show,
        kind: attrs["kind"].presence || "unknown",
        format: attrs["format"].presence || "unknown",
        provider: attrs["provider"].presence || "link",
        external_id: attrs["external_id"],
        url: attrs["url"],
        upload_id: attrs["upload_id"],
        title: attrs["title"],
        taper_id: attrs["taper_id"],
        taper_name: attrs["taper_name"],
        lineage: attrs["lineage"],
        duration_seconds: attrs["duration_seconds"],
        submitted_by: suggestion.submitted_by,
      )
    end

    ALLOWED_CORRECTIONS = %w[venue city region country tour setlist notes date].freeze

    def apply_correction(suggestion)
      changes = suggestion.payload["changes"].slice(*ALLOWED_CORRECTIONS)
      changes["date"] = Date.parse(changes["date"]) if changes["date"]
      show = suggestion.show
      show.update!(changes)
      if suggestion.payload["setlistfm_id"].present? && show.setlistfm_id.blank?
        show.update!(setlistfm_id: suggestion.payload["setlistfm_id"])
      end
      if changes["venue"]
        link_venue!(
          show,
          changes["venue"],
          city: show.city,
          region: show.region,
          country: show.country,
        )
      end
      show
    end
  end
end
