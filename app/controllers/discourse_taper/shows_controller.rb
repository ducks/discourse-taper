# frozen_string_literal: true

module DiscourseTaper
  # The archive's read side, as HTML for readers and JSON on a .json
  # suffix, plus the manual channel (suggest). Everything readable here
  # is visible to whoever can see the archive category, so a private
  # archive stays private.
  class ShowsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :preload_json, :check_xhr, only: %i[band show bands suggest_form suggest]
    before_action :ensure_logged_in, only: %i[suggest]
    before_action :ensure_can_see_archive
    before_action :load_bands, only: %i[band show bands suggest_form suggest]

    prepend_view_path File.expand_path("../../views", __dir__)
    layout "taper"
    helper_method :duration,
                  :festival?,
                  :embed_url,
                  :month_name,
                  :weekday_name,
                  :forum_url,
                  :json_url

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
      # The same page answers at / when the archive is the site homepage;
      # /taper stays canonical.
      canonical(request.query_string.present? ? "#{@band.url}?#{request.query_string}" : @band.url)

      if json_request?
        render json: {
                 band: BandSerializer.new(@band, root: false).as_json,
                 years: @years.map { |year, count| { year: year, count: count } },
                 shows: @shows.map { |show| show_summary(show) },
               }
      elsif @year || params[:venue].present? || params[:tour].present?
        cache_for_anonymous
        prepare_listing(shows)
        render_page(:listing)
      else
        cache_for_anonymous
        prepare_front_door
        render_page(:band)
      end
    end

    def show
      @band = find_band!
      @show = find_show!(@band, params[:date])
      @sources = @show.sources.includes(:taper, :upload).order(:created_at).to_a
      @previous_show, @next_show = neighbours(@show)
      canonical(@show.url)

      if json_request?
        render json: { show: ShowSerializer.new(@show, root: false, scope: guardian).as_json }
      else
        cache_for_anonymous
        @player = @sources.find { |source| embed_url(source) }
        @runtime = @sources.filter_map(&:duration_seconds).max
        @reply_count, @replies = latest_replies(@show.topic)
        render_page(:show)
      end
    end

    # GET /taper(/:band)/suggest(?date=...)
    # The manual channel's form. With a date it offers a recording and a
    # correction for that show; without one, a missing show.
    def suggest_form
      @band = find_band!
      @show = params[:date].present? ? find_show!(@band, params[:date]) : nil
      response.headers["Cache-Control"] = "private, no-store"
      render_page(:suggest)
    end

    # POST /taper(/:band)/suggest
    # Members propose a show, a source for a show, or a correction;
    # reviewers accept or reject in the queue. Answers JSON to API and
    # XHR callers and a confirmation page to the browser form.
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
      payload = with_setlist_text(payload, kind)
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
      if json_request?
        render json: { suggestion: SuggestionSerializer.new(suggestion, root: false).as_json }
      else
        @band = band
        @back_url = show&.url || band.url
        response.headers["Cache-Control"] = "private, no-store"
        render_page(:suggested)
      end
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

    # Core's head partial emits the canonical link from @canonical_url, so
    # the reader sets it absolute there and keeps the path for its own use.
    def canonical(path)
      @canonical_path = path
      @canonical_url = "#{Discourse.base_url_no_prefix}#{path}"
    end

    # Where "the forum" is. Normally the site root; when the archive is the
    # site homepage, the root is this page, so the first topic list instead.
    def forum_url
      return "#{Discourse.base_path}/" if SiteSetting.default_homepage != "taper"
      "#{Discourse.base_path}/#{SiteSetting.top_menu_items.first&.name || "latest"}"
    end

    # The JSON twin of the page being viewed, by its canonical path so it is
    # right at / too.
    def json_url
      base = (@canonical_path.presence || request.path).split("?", 2)
      "#{base[0]}.json#{"?#{base[1]}" if base[1].present?}"
    end

    # Localised names where the locale has them, strftime where it does
    # not (the test locale ships no day names).
    def month_name(date)
      names = I18n.t("date.month_names", default: nil)
      names.is_a?(Array) && names[date.month] ? names[date.month] : date.strftime("%B")
    end

    def weekday_name(date)
      names = I18n.t("date.abbr_day_names", default: nil)
      names.is_a?(Array) && names[date.wday] ? names[date.wday] : date.strftime("%a")
    end

    # The archive has no festival field; the word in the venue or tour
    # is what marks one in the listing.
    def festival?(show)
      "#{show.venue} #{show.tour}".match?(/\bfest(ival)?\b/i)
    end

    # An embeddable player for a source, or nil. YouTube through the
    # cookieless host; archive.org through its own embed.
    def embed_url(source)
      case source.provider
      when "youtube"
        id = source.external_id.presence || youtube_id(source.url)
        id && "https://www.youtube-nocookie.com/embed/#{ERB::Util.url_encode(id)}"
      when "archive_org"
        id = source.external_id.presence || source.url.to_s[%r{archive\.org/details/([^/?#]+)}, 1]
        id && "https://archive.org/embed/#{ERB::Util.url_encode(id)}"
      end
    end

    def youtube_id(url)
      url.to_s[%r{(?:youtu\.be/|[?&]v=|/embed/|/shorts/)([A-Za-z0-9_-]{6,})}, 1]
    end

    # Front door: every year from the first show to the latest (gap years
    # included, so a hiatus shows as a gap), the latest recordings, and
    # the headline counts.
    def prepare_front_door
      counts = @years.to_h
      if counts.any?
        first, last = counts.keys.minmax
        peak = counts.values.max.to_f
        @spines =
          (first..last).map do |year|
            count = counts.fetch(year, 0)
            [year, count, count.zero? ? 2 : [(count / peak * 100).round, 6].max]
          end
      else
        @spines = []
      end
      @latest_sources =
        Source
          .joins(:show)
          .where(taper_shows: { band_id: @band.id })
          .includes(:taper, show: :band)
          .order(created_at: :desc)
          .limit(6)
          .to_a
      @stats = {
        shows: @band.shows.count,
        recordings: Source.joins(:show).where(taper_shows: { band_id: @band.id }).count,
        years: counts.size,
      }
    end

    # A year, a venue, or a tour: the same month-grouped listing under a
    # monumental heading.
    def prepare_listing(scope)
      @listing_title = @year&.to_s || params[:venue].presence || params[:tour].presence
      total = scope.count
      @truncated = total > @shows.size
      @listing_stats = {
        shows: total,
        recordings: @shows.sum { |show| show.sources.size },
        venues: @shows.map(&:venue).uniq.size,
        tours: @year ? @shows.filter_map(&:tour).uniq : [],
      }
    end

    # How many replies the show's topic has and the two newest, for the
    # reader who has not stepped into the forum yet. Whispers and hidden
    # posts stay out.
    def latest_replies(topic)
      replies =
        Post.where(
          topic_id: topic.id,
          post_type: Post.types[:regular],
          hidden: false,
          deleted_at: nil,
        ).where("post_number > 1")
      [replies.count, replies.includes(:user).order(created_at: :desc).limit(2).to_a.reverse]
    end

    def json_request?
      params[:format].to_s == "json" || request.xhr?
    end

    # The browser forms take the setlist as one song per line; the API
    # sends it structured. Normalise to the structured form the reviewer
    # applies. A line like "Scarlet Begonias >" keeps the segue as notes.
    def with_setlist_text(payload, kind)
      text = params[:setlist_text].to_s
      return payload if text.blank?

      songs =
        text
          .lines
          .map(&:strip)
          .reject(&:blank?)
          .map do |line|
            title, notes = line.split(/\s+(?=[>-]\s*\z)/, 2)
            { "title" => title.to_s.strip, "notes" => notes&.strip }.compact
          end
      if kind == "correction"
        payload["changes"] ||= {}
        payload["changes"]["setlist"] = songs
      else
        payload["setlist"] = songs
      end
      payload
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
