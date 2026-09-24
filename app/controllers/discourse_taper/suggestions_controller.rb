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

    # POST /taper/suggestions/accept_all.json { origin, band_id?, kind? }
    # Accepts every pending suggestion an importer filed, in a job. Meant
    # for a trusted show source (setlist.fm) whose first import is a few
    # hundred shows nobody wants to click through one at a time. The ids
    # are fixed at request time so nothing filed later rides along.
    def accept_all
      origin = params[:origin].to_s
      if !Jobs::TaperImportFeed.importers.key?(origin)
        raise Discourse::InvalidParameters.new(:origin)
      end
      kind = params[:kind].presence || "new_show"
      raise Discourse::InvalidParameters.new(:kind) if !Suggestion::KINDS.include?(kind)

      scope = Suggestion.pending.where(origin: origin, kind: kind)
      scope = scope.where(band_id: params[:band_id]) if params[:band_id].present?
      ids = scope.order(:id).pluck(:id)
      if ids.any?
        Jobs.enqueue(
          :taper_accept_suggestions,
          suggestion_ids: ids,
          origin: origin,
          reviewer_id: current_user.id,
        )
      end
      render json: { queued: ids.size }
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
