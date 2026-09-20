# frozen_string_literal: true

module DiscourseTaper
  # Turns an accepted suggestion into records. Rejection just records who
  # said no and why, so an importer will not re-propose the same item.
  class SuggestionReviewer
    def initialize(reviewer:)
      @reviewer = reviewer
    end

    def accept!(suggestion, note: nil)
      raise Error.new("not_pending") if !suggestion.pending?

      result =
        Suggestion.transaction do
          created =
            case suggestion.kind
            when "new_show"
              create_show(suggestion)
            when "new_source"
              create_source(suggestion)
            when "correction"
              apply_correction(suggestion)
            end
          suggestion.update!(
            status: "accepted",
            reviewed_by: @reviewer,
            reviewed_at: Time.zone.now,
            review_note: note,
          )
          created
        end

      result
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
      # An importer's new-show suggestion usually carries the source it
      # found; attach it in the same acceptance.
      attach_source(show, p["source"], suggestion) if p["source"].is_a?(Hash)
      show
    end

    def create_source(suggestion)
      show = suggestion.show
      if show.nil?
        show =
          ShowMatcher.new(band: suggestion.band).find(
            date: Date.parse(suggestion.payload["date"]),
            venue: suggestion.payload["venue"],
          )
        raise Error.new("show_not_found") if show.nil?
      end
      attach_source(show, suggestion.payload, suggestion)
    end

    def attach_source(show, attrs, suggestion)
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
      show
    end
  end
end
