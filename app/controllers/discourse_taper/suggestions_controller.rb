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
      created =
        SuggestionReviewer.new(reviewer: current_user).accept!(suggestion, note: params[:note])
      render json: {
               suggestion: SuggestionSerializer.new(suggestion.reload, root: false).as_json,
               show_url: created.respond_to?(:url) ? created.url : created.show.url,
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
      importer = Jobs::TaperImportFeed::IMPORTERS[params[:importer].to_s]
      raise Discourse::InvalidParameters.new(:importer) if importer.nil? || !importer.available?
      Jobs.enqueue(:taper_import_feed, band_id: band.id, importer: importer.key)
      render json: success_json
    end

    private

    def ensure_reviewer
      allowed = SiteSetting.taper_reviewer_groups.to_s.split("|").map(&:to_i)
      ok =
        current_user.staff? ||
          (allowed.any? && GroupUser.exists?(group_id: allowed, user_id: current_user.id))
      raise Discourse::InvalidAccess if !ok
    end
  end
end
