# frozen_string_literal: true

module DiscourseTaper
  # One recording's own page, and how a reviewer manages it: fix its
  # details, move it to the night it belongs to, or take it off the
  # archive. Readers see what the show page shows, in full.
  class RecordingsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :preload_json, :check_xhr, only: %i[show]
    before_action :ensure_logged_in, only: %i[update move destroy]
    before_action :ensure_reviewer, only: %i[update move destroy]
    before_action :ensure_can_see_archive
    before_action :find_source

    prepend_view_path File.expand_path("../../views", __dir__)
    layout "taper"
    helper_method :duration, :embed_url, :forum_url, :json_url, :locale_links

    # "format" is Rails' own request-format param (".json"), so the
    # recording's format travels as recording_format.
    EDITABLE = %i[title kind taper_name lineage url].freeze

    def show
      @show = @source.show
      @band = @show.band
      @bands = Band.order(:name).to_a
      @primary_band = @bands.find(&:primary?)
      @canonical_path = "#{DiscourseTaper.root_path}/recordings/#{@source.id}"
      @canonical_url = "#{Discourse.base_url_no_prefix}#{@canonical_path}"
      response.headers["Cache-Control"] = "private, no-store"

      if request.format.json? || params[:format] == "json"
        render json: {
                 recording: SourceSerializer.new(@source, root: false, scope: guardian).as_json,
               }
      else
        request.format = :html
        render :show, content_type: "text/html"
      end
    end

    def update
      attributes = params.permit(*EDITABLE).to_h
      attributes["format"] = params[:recording_format] if params[:recording_format].present?
      @source.update!(attributes)
      respond_with_source
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.record.errors.full_messages.join(", "), status: 422)
    end

    # Moves the recording to this band's show on another date.
    def move
      date = Date.iso8601(params[:date].to_s)
      target = @source.show.band.shows.find_by(date: date, sequence: (params[:sequence] || 1).to_i)
      raise Discourse::NotFound if target.nil?
      @source.update!(show: target)
      respond_with_source
    rescue Date::Error
      raise Discourse::InvalidParameters.new(:date)
    end

    # Removes the recording and leaves a rejected suggestion behind, so the
    # importer that found it does not bring it back.
    def destroy
      show = @source.show
      Source.transaction do
        if @source.provider != "upload" && @source.external_id.present?
          Suggestion.create!(
            kind: "new_source",
            band: show.band,
            show: show,
            origin: @source.provider,
            status: "rejected",
            reviewed_by: current_user,
            reviewed_at: Time.zone.now,
            review_note: I18n.t("taper.recording.removed_note"),
            payload: {
              "date" => show.date.iso8601,
              "sources" => [
                {
                  "provider" => @source.provider,
                  "external_id" => @source.external_id,
                  "url" => @source.url,
                  "title" => @source.title,
                },
              ],
            },
          )
        end
        @source.destroy!
      end
      if json_request?
        render json: success_json.merge(show_url: show.url)
      else
        redirect_to show.url
      end
    end

    private

    def respond_with_source
      if json_request?
        render json: {
                 recording:
                   SourceSerializer.new(@source.reload, root: false, scope: guardian).as_json,
               }
      else
        redirect_to "#{DiscourseTaper.root_path}/recordings/#{@source.id}"
      end
    end

    def json_request?
      params[:format].to_s == "json" || request.xhr?
    end

    def find_source
      @source = Source.includes(:taper, :upload, show: :band).find_by(id: params[:id])
      raise Discourse::NotFound if @source.nil? || !guardian.can_see_topic?(@source.show.topic)
    end

    def ensure_reviewer
      raise Discourse::InvalidAccess if !DiscourseTaper.reviewer?(current_user)
    end

    def ensure_can_see_archive
      category = DiscourseTaper.category
      raise Discourse::NotFound if category.nil? || !guardian.can_see_category?(category)
    end

    def duration(seconds)
      return nil if seconds.to_i <= 0
      h, rem = seconds.to_i.divmod(3600)
      m = rem / 60
      h.positive? ? format("%dh %02dm", h, m) : "#{m}m"
    end

    def embed_url(source)
      case source.provider
      when "youtube"
        id =
          source.external_id.presence ||
            source.url.to_s[%r{(?:youtu\.be/|[?&]v=|/embed/|/shorts/)([A-Za-z0-9_-]{6,})}, 1]
        id && "https://www.youtube-nocookie.com/embed/#{ERB::Util.url_encode(id)}"
      when "archive_org"
        id = source.external_id.presence || source.url.to_s[%r{archive\.org/details/([^/?#]+)}, 1]
        id && "https://archive.org/embed/#{ERB::Util.url_encode(id)}"
      end
    end

    def forum_url
      return "#{Discourse.base_path}/" if SiteSetting.default_homepage != "taper"
      "#{Discourse.base_path}/#{SiteSetting.top_menu_items.first&.name || "latest"}"
    end

    def json_url
      "#{@canonical_path}.json"
    end

    def locale_links
      DiscourseTaper.reader_locales.map do |locale|
        {
          locale: locale,
          url: "#{@canonical_path}?lang=#{locale}",
          current: I18n.locale.to_s == locale,
        }
      end
    end
  end
end
