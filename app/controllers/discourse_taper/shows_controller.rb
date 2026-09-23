# frozen_string_literal: true

module DiscourseTaper
  # The archive's read side, as HTML for readers and JSON on a .json
  # suffix, plus the manual channel (suggest). Everything readable here
  # is visible to whoever can see the archive category, so a private
  # archive stays private.
  class ShowsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :preload_json, :check_xhr, only: %i[band show bands]
    before_action :ensure_logged_in, only: %i[suggest]
    before_action :ensure_can_see_archive
    before_action :load_bands, only: %i[band show bands]

    prepend_view_path File.expand_path("../../views", __dir__)
    layout "taper"
    helper_method :duration

    def bands
      bands =
        Band
          .left_joins(:shows)
          .select("taper_bands.*, COUNT(taper_shows.id) AS show_count")
          .group("taper_bands.id")
          .order(:name)
      render json: { bands: serialize_data(bands, BandSerializer, root: false) }
    end

    def band
      @band = find_band!
      @year = params[:year].presence&.to_i
      shows = @band.shows.includes(:topic, :sources).by_date
      shows = shows.for_year(@year) if @year
      shows = shows.where(venue: params[:venue]) if params[:venue].present?
      shows = shows.where(tour: params[:tour]) if params[:tour].present?
      @shows = shows.limit(500).to_a
      @years = @band.shows.group("EXTRACT(YEAR FROM date)::int").count.sort.reverse

      if json_request?
        render json: {
                 band: BandSerializer.new(@band, root: false).as_json,
                 years: @years.map { |year, count| { year: year, count: count } },
                 shows: @shows.map { |show| show_summary(show) },
               }
      else
        cache_for_anonymous
        render_page(:band)
      end
    end

    def show
      @band = find_band!
      @show = find_show!(@band, params[:date])
      @sources = @show.sources.includes(:taper, :upload).order(:created_at).to_a
      @previous_show, @next_show = neighbours(@show)
      @canonical_url = @show.url

      if json_request?
        render json: { show: ShowSerializer.new(@show, root: false, scope: guardian).as_json }
      else
        cache_for_anonymous
        render_page(:show)
      end
    end

    # POST /taper(/:band)/suggest.json
    # The manual channel. Members propose a show, a source for a show, or a
    # correction; reviewers accept or reject in the queue.
    def suggest
      band = find_band!
      kind = params[:kind].to_s
      raise Discourse::InvalidParameters.new(:kind) if !Suggestion::KINDS.include?(kind)

      show =
        if params[:date].present?
          ShowMatcher.new(band: band).find(date: parse_date(params[:date]), venue: params[:venue])
        end
      raise Discourse::NotFound if kind == "correction" && show.nil?

      payload = params.require(:payload).permit!.to_h
      suggestion =
        Suggestion.create!(
          kind: kind,
          band: band,
          show: show,
          payload: payload,
          submitted_by: current_user,
          origin: "user",
          note: params[:note].to_s.presence,
        )
      render json: { suggestion: SuggestionSerializer.new(suggestion, root: false).as_json }
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.record.errors.full_messages.join(", "), status: 422)
    end

    private

    # "2h 26m" or "48m" for the reader surface.
    def duration(seconds)
      return nil if seconds.to_i <= 0
      h, rem = seconds.to_i.divmod(3600)
      m = rem / 60
      h.positive? ? format("%dh %02dm", h, m) : "#{m}m"
    end

    def json_request?
      params[:format].to_s == "json" || request.xhr?
    end

    # Readers get HTML whatever the app layer infers from headers.
    def render_page(template)
      request.format = :html
      render template, content_type: "text/html"
    end

    # Anonymous readers go through the anonymous cache with a short
    # browser cache; signed-in readers may see restricted archives and are
    # never cached.
    def cache_for_anonymous
      if current_user.nil?
        discourse_expires_in 1.minute
        expires_in 1.minute, public: true
      else
        response.headers["Cache-Control"] = "private, no-store"
      end
    end

    def load_bands
      @bands = Band.order(:name).to_a
      @primary_band = @bands.find(&:primary?)
    end

    def ensure_can_see_archive
      category = DiscourseTaper.category
      raise Discourse::NotFound if category.nil? || !guardian.can_see_category?(category)
    end

    # No :band param means the primary band, which is what the short URLs
    # (/taper, /taper/1977-05-08) resolve to.
    def find_band!
      band = params[:band].present? ? Band.find_by(slug: params[:band]) : Band.primary_band
      band || raise(Discourse::NotFound)
    end

    def find_show!(band, slug)
      date_part, seq = slug.to_s.split(/-(?=\d+\z)/, 2) if slug.to_s.length > 10
      date_part ||= slug
      show =
        band.shows.includes(:topic).find_by(date: parse_date(date_part), sequence: (seq || 1).to_i)
      raise Discourse::NotFound if show.nil? || !guardian.can_see_topic?(show.topic)
      show
    end

    def neighbours(show)
      list = show.band.shows.by_date.to_a.reverse
      index = list.index { |s| s.id == show.id }
      return nil, nil if index.nil?
      [index.positive? ? list[index - 1] : nil, list[index + 1]]
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Discourse::InvalidParameters.new(:date)
    end

    def show_summary(show)
      {
        id: show.id,
        date: show.date,
        label: show.label,
        venue: show.venue,
        city: show.city,
        tour: show.tour,
        url: show.url,
        topic_url: show.topic&.relative_url,
        source_count: show.sources.size,
      }
    end
  end
end
