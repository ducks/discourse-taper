# frozen_string_literal: true

module DiscourseTaper
  # Band management for reviewers, so an archive is settable without a
  # console: name, description, and the identifiers the importers use.
  class BandsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_reviewer

    def index
      render json: { bands: serialize_data(Band.order(:name), BandSerializer, root: false) }
    end

    def create
      band = Band.create!(band_params)
      render json: { band: BandSerializer.new(band, root: false).as_json }
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.record.errors.full_messages.join(", "), status: 422)
    end

    def update
      band = Band.find(params[:id])
      band.update!(band_params)
      band.make_primary! if params[:primary].to_s == "true" && !band.primary?
      render json: { band: BandSerializer.new(band.reload, root: false).as_json }
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.record.errors.full_messages.join(", "), status: 422)
    end

    def destroy
      band = Band.find(params[:id])
      if band.shows.exists?
        return render_json_error(I18n.t("taper.errors.band_has_shows"), status: 422)
      end
      band.destroy!
      render json: success_json
    end

    private

    def band_params
      params.permit(
        :name,
        :slug,
        :description,
        :footer,
        :archive_org_collection,
        :archive_org_query,
        :youtube_channel_id,
        :youtube_search_query,
        :setlistfm_artist_name,
        :auto_accept_recordings,
      )
    end

    def ensure_reviewer
      raise Discourse::InvalidAccess if !DiscourseTaper.reviewer?(current_user)
    end
  end
end
