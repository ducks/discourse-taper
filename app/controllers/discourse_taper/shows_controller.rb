# frozen_string_literal: true

module DiscourseTaper
  # Read side of the archive plus the manual channel (suggest). Everything
  # readable here is visible to whoever can see the archive category, so
  # a private archive stays private.
  class ShowsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in, only: %i[suggest]
    before_action :ensure_can_see_archive

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
      band = find_band!
      shows = band.shows.includes(:topic).by_date
      shows = shows.for_year(params[:year].to_i) if params[:year].present?
      shows = shows.where(venue: params[:venue]) if params[:venue].present?
      shows = shows.where(tour: params[:tour]) if params[:tour].present?

      years = band.shows.group("EXTRACT(YEAR FROM date)::int").count.sort.reverse
      render json: {
               band: BandSerializer.new(band, root: false).as_json,
               years: years.map { |year, count| { year: year, count: count } },
               shows: shows.limit(500).map { |show| show_summary(show) },
             }
    end

    def show
      band = find_band!
      show = find_show!(band, params[:date])
      render json: { show: ShowSerializer.new(show, root: false, scope: guardian).as_json }
    end

    # POST /taper/:band/suggest.json
    # The manual channel. Members propose a show, a source for a show, or a
    # correction; reviewers accept or reject in the queue.
    def suggest
      band = find_band!
      kind = params[:kind].to_s
      raise Discourse::InvalidParameters.new(:kind) if !Suggestion::KINDS.include?(kind)

      show =
        (
          if params[:date].present?
            ShowMatcher.new(band: band).find(date: parse_date(params[:date]), venue: params[:venue])
          else
            nil
          end
        )
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

    def ensure_can_see_archive
      category = DiscourseTaper.category
      raise Discourse::NotFound if category.nil? || !guardian.can_see_category?(category)
    end

    def find_band!
      Band.find_by(slug: params[:band]) || raise(Discourse::NotFound)
    end

    def find_show!(band, slug)
      date_part, seq = slug.to_s.split(/-(?=\d+\z)/, 2) if slug.to_s.length > 10
      date_part ||= slug
      show = band.shows.find_by(date: parse_date(date_part), sequence: (seq || 1).to_i)
      raise Discourse::NotFound if show.nil? || !guardian.can_see_topic?(show.topic)
      show
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
