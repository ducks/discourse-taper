# frozen_string_literal: true

module DiscourseTaper
  # The review queue. Members of the reviewer groups accept or reject
  # what importers and other members have proposed.
  class SuggestionsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_reviewer

    def index
      suggestions = Suggestion.pending.includes(:band, :show, :submitted_by).limit(200)
      render json: { suggestions: serialize_data(suggestions, SuggestionSerializer, root: false) }
    end

    def accept
      suggestion = Suggestion.find(params[:id])
      # A reviewer may correct the proposed venue name before accepting; the
      # name they type becomes the canonical one.
      if params[:venue].present? && suggestion.kind == "new_show"
        corrected = params[:venue].to_s.strip[0, 200]
        original = suggestion.payload["venue"]
        if original.present? && original != corrected
          # The spelling being corrected is exactly the alias worth learning.
          spellings = suggestion.payload["venue_spellings"] || {}
          suggestion.payload["venue_spellings"] = spellings.merge(
            original => spellings[original] || 1,
          )
        end
        suggestion.payload["venue"] = corrected
        suggestion.save!
      end
      show = SuggestionReviewer.new(reviewer: current_user).accept!(suggestion, note: params[:note])
      render json: {
               suggestion: SuggestionSerializer.new(suggestion.reload, root: false).as_json,
               show_url: show.url,
             }
    rescue DiscourseTaper::Error => e
      render_json_error(e.message, status: 422)
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.record.errors.full_messages.join(", "), status: 422)
    end

    def reject
      suggestion = Suggestion.find(params[:id])
      SuggestionReviewer.new(reviewer: current_user).reject!(suggestion, note: params[:note])
      render json: { suggestion: SuggestionSerializer.new(suggestion.reload, root: false).as_json }
    rescue DiscourseTaper::Error => e
      render_json_error(e.message, status: 422)
    end

    # POST /taper/suggestions/import.json { band_id, importer }
    # Lets a reviewer kick an importer for one band without waiting for
    # the schedule.
    def import
      band = Band.find(params[:band_id])
      importer = Jobs::TaperImportFeed.importers[params[:importer].to_s]
      raise Discourse::InvalidParameters.new(:importer) if importer.nil? || !importer.available?
      Jobs.enqueue(:taper_import_feed, band_id: band.id, importer: importer.key)
      render json: success_json
    end

    private

    def ensure_reviewer
      raise Discourse::InvalidAccess if !DiscourseTaper.reviewer?(current_user)
    end
  end
end
