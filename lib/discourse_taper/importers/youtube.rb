# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Finds a band's videos through the YouTube Data API two ways: the
    # uploads of a channel the band names, and a search for a query the
    # band names. For a band whose tapes are scattered across fans'
    # channels the search is the one that matters.
    #
    # YouTube has no structured venue or date, so both are recovered from
    # the title and description. A video with no recognisable date is
    # matched to a show the archive already knows (or has pending) whose
    # venue or city the video mentions, within a month before it was
    # published. Anything still undated is skipped.
    class Youtube < Base
      ENDPOINT = "https://www.googleapis.com/youtube/v3"
      MAX_UPLOAD_PAGES = 20
      # A search costs 100 quota units of a 10,000 daily allowance.
      MAX_SEARCH_PAGES = 10
      INFERENCE_WINDOW = 31

      def self.key
        "youtube"
      end

      def self.available?
        SiteSetting.taper_youtube_api_key.present?
      end

      private

      def each_item(&block)
        return if !self.class.available?

        seen = Set.new
        if band.youtube_channel_id.present?
          each_upload_page { |videos| yield_videos(videos, seen, &block) }
        end
        if band.youtube_search_query.present?
          each_search_page do |videos|
            yield_videos(videos.select { |video| mentions_band?(video) }, seen, &block)
          end
        end
      end

      def yield_videos(videos, seen)
        videos =
          videos.reject { |video| video[:video_id].blank? || seen.include?(video[:video_id]) }
        return if videos.empty?
        durations = durations_for(videos.map { |video| video[:video_id] })
        videos.each do |video|
          seen << video[:video_id]
          yield item_from(video, durations[video[:video_id]])
        end
      end

      def each_upload_page
        playlist = uploads_playlist(band.youtube_channel_id)
        return if playlist.blank?

        token = nil
        pages = 0
        loop do
          data = fetch_playlist_page(playlist, token)
          yield(
            Array(data["items"]).map do |entry|
              video_from(entry, entry.dig("snippet", "resourceId", "videoId"))
            end
          )
          token = data["nextPageToken"]
          pages += 1
          break if token.blank? || pages >= MAX_UPLOAD_PAGES
        end
      end

      def each_search_page
        token = nil
        pages = 0
        loop do
          data = fetch_search_page(band.youtube_search_query, token)
          yield Array(data["items"]).map { |entry| video_from(entry, entry.dig("id", "videoId")) }
          token = data["nextPageToken"]
          pages += 1
          break if token.blank? || pages >= MAX_SEARCH_PAGES
        end
      end

      def uploads_playlist(channel)
        params = URI.encode_www_form(part: "contentDetails", id: channel, key: api_key)
        get_json("#{ENDPOINT}/channels?#{params}").dig(
          "items",
          0,
          "contentDetails",
          "relatedPlaylists",
          "uploads",
        )
      end

      def fetch_playlist_page(playlist, token)
        params = { part: "snippet", playlistId: playlist, maxResults: page_size, key: api_key }
        params[:pageToken] = token if token
        get_json("#{ENDPOINT}/playlistItems?#{URI.encode_www_form(params)}")
      end

      # Long videos only: a full set, not a phone clip of one song.
      def fetch_search_page(query, token)
        params = {
          part: "snippet",
          q: query,
          type: "video",
          videoDuration: "long",
          order: "date",
          maxResults: page_size,
          key: api_key,
        }
        params[:pageToken] = token if token
        get_json("#{ENDPOINT}/search?#{URI.encode_www_form(params)}")
      end

      # Search and playlist snippets carry no duration; one cheap videos
      # call per page fills it in.
      def durations_for(video_ids)
        params = URI.encode_www_form(part: "contentDetails", id: video_ids.join(","), key: api_key)
        Array(get_json("#{ENDPOINT}/videos?#{params}")["items"]).to_h do |entry|
          [entry["id"], iso8601_seconds(entry.dig("contentDetails", "duration"))]
        end
      rescue Error
        {}
      end

      def video_from(entry, video_id)
        snippet = entry["snippet"] || {}
        {
          video_id: video_id,
          title: snippet["title"],
          description: snippet["description"],
          channel_title: snippet["channelTitle"],
          published_at:
            (Time.zone.parse(snippet["publishedAt"]) if snippet["publishedAt"].present?),
        }
      end

      def item_from(video, duration)
        text = "#{video[:title]} #{video[:description]}"
        {
          external_id: video[:video_id],
          url: "https://www.youtube.com/watch?v=#{video[:video_id]}",
          title: video[:title],
          date:
            ShowMatcher.extract_date(text, year_hint: video[:published_at]) ||
              infer_date(text, video[:published_at]),
          venue: venue_from(video[:title]),
          kind: "video",
          format: "video",
          taper_name: video[:channel_title],
          duration_seconds: duration,
        }
      end

      # A search for the band's name returns some noise; keep a video only
      # when the band is actually named in it.
      def mentions_band?(video)
        text = Venue.normalize("#{video[:title]} #{video[:description]} #{video[:channel_title]}")
        text.include?(Venue.normalize(band.name))
      end

      # Undated video, published shortly after a show it names by venue or
      # city: that show. Ambiguity (two shows in the window both named)
      # leaves it undated rather than guessing.
      def infer_date(text, published_at)
        return nil if published_at.nil?
        haystack = Venue.normalize(text)
        window = (published_at.to_date - INFERENCE_WINDOW)..published_at.to_date
        dates =
          known_shows
            .select { |show| window.cover?(show[:date]) }
            .select do |show|
              [show[:venue], show[:city]].any? { |place| mentions?(haystack, place) }
            end
            .map { |show| show[:date] }
            .uniq
        dates.size == 1 ? dates.first : nil
      end

      def mentions?(haystack, place)
        needle = Venue.normalize(place)
        needle.length >= 4 && haystack.include?(needle)
      end

      def known_shows
        @known_shows ||=
          begin
            shows =
              Show
                .where(band: band)
                .map { |show| { date: show.date, venue: show.venue, city: show.city } }
            pending =
              Suggestion
                .where(band: band, kind: "new_show", status: "pending")
                .map do |suggestion|
                  p = suggestion.payload
                  { date: ShowMatcher.safe_iso(p["date"]), venue: p["venue"], city: p["city"] }
                end
            (shows + pending).select { |show| show[:date] }
          end
      end

      # "Band - 5/8/77 - Barton Hall, Ithaca NY" => "Barton Hall, Ithaca NY".
      # Takes the segment after the date when the title is dash-delimited;
      # otherwise nothing, and the matcher falls back to date alone.
      def venue_from(title)
        parts = title.to_s.split(/\s+[-–|]\s+/)
        return nil if parts.size < 2
        idx = parts.index { |p| ShowMatcher.extract_date(p) }
        return nil if idx.nil? || parts[idx + 1].blank?
        parts[idx + 1].strip
      end

      # "PT1H2M3S" => 3723
      def iso8601_seconds(value)
        m = value.to_s.match(/\APT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?\z/)
        return nil if m.nil?
        m[1].to_i * 3600 + m[2].to_i * 60 + m[3].to_i
      end

      def api_key
        SiteSetting.taper_youtube_api_key
      end

      def page_size
        [SiteSetting.taper_import_page_size, 50].min
      end
    end
  end
end
