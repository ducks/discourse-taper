# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Finds a band's videos on YouTube. With an API key: the uploads of a
    # channel the band names, and a search for a query the band names. For
    # a band whose tapes are scattered across fans' channels the search is
    # the one that matters. Without a key, and when the site allows it,
    # the same search is read off YouTube's result pages instead, which
    # carry title, channel, duration, and a rough age.
    #
    # YouTube has no structured venue or date, so both are recovered from
    # the title and description. A date that reads two ways (10/05/2026)
    # is settled by which reading lands on a known show. A video with no
    # date is matched to a show the archive already knows (or has pending)
    # whose venue or city it names: the one show at that place in the
    # year the title gives, else the one show at that place in the month
    # before the video was published, else the one show ever at that
    # place. Anything still undated is skipped.
    class Youtube < Base
      ENDPOINT = "https://www.googleapis.com/youtube/v3"
      RESULTS_PAGE = "https://www.youtube.com/results"
      # YouTube's "long" duration filter, over twenty minutes: a full set,
      # not a phone clip of one song.
      LONG_FILTER = "EgIYAg=="
      MAX_UPLOAD_PAGES = 20
      # A search costs 100 quota units of a 10,000 daily allowance.
      MAX_SEARCH_PAGES = 10
      # Result pages carry about twenty videos each and overlap heavily
      # between phrasings; four phrasings find nearly every full set.
      # Each phrasing with whether to keep YouTube's long-video filter on:
      # full sets are long, interviews are not.
      SCRAPE_QUERIES = [
        ["full set", true],
        ["live", true],
        ["concert complet", true],
        ["", true],
        ["interview", false],
        ["entrevue", false],
      ].freeze
      BROWSER_UA =
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"

      def self.key
        "youtube"
      end

      def self.available?
        SiteSetting.taper_youtube_api_key.present? || SiteSetting.taper_youtube_scrape_enabled
      end

      private

      def each_item(&block)
        return if !self.class.available?

        seen = Set.new
        if api_key.present?
          if band.youtube_channel_id.present?
            each_upload_page { |videos| yield_videos(videos, seen, &block) }
          end
          if band.youtube_search_query.present?
            each_search_page do |videos|
              yield_videos(videos.select { |video| mentions_band?(video) }, seen, &block)
            end
          end
        elsif SiteSetting.taper_youtube_scrape_enabled && band.youtube_search_query.present?
          each_scraped_page do |videos|
            yield_videos(videos.select { |video| mentions_band?(video) }, seen, &block)
          end
        end
      end

      def yield_videos(videos, seen)
        videos =
          videos.reject { |video| video[:video_id].blank? || seen.include?(video[:video_id]) }
        return if videos.empty?
        durations = durations_for(videos)
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

      # One result page per phrasing of the query, long videos only.
      def each_scraped_page
        SCRAPE_QUERIES.each do |suffix, long|
          query = [band.youtube_search_query, suffix].reject(&:blank?).join(" ")
          query_params = { search_query: query }
          query_params[:sp] = LONG_FILTER if long
          params = URI.encode_www_form(query_params)
          html =
            get_html(
              "#{RESULTS_PAGE}?#{params}",
              headers: {
                "User-Agent" => BROWSER_UA,
                "Accept-Language" => "en-US,en;q=0.9",
                # Skips the consent interstitial YouTube serves in some regions.
                "Cookie" => "CONSENT=YES+cb; SOCS=CAI",
              },
            )
          yield scraped_videos(html)
        end
      end

      # The result page embeds its data as JSON; every videoRenderer in it
      # is one result.
      def scraped_videos(html)
        json = html.to_s[/var ytInitialData = (\{.*?\});<\/script>/m, 1]
        return [] if json.blank?
        renderers = []
        collect_renderers(JSON.parse(json), renderers)
        renderers.map { |r| scraped_video(r) }
      rescue JSON::ParserError
        []
      end

      def collect_renderers(node, out)
        case node
        when Hash
          out << node["videoRenderer"] if node["videoRenderer"].is_a?(Hash)
          node.each_value { |value| collect_renderers(value, out) }
        when Array
          node.each { |value| collect_renderers(value, out) }
        end
      end

      def scraped_video(r)
        snippet =
          Array(r.dig("detailedMetadataSnippets", 0, "snippetText", "runs"))
            .map { |run| run["text"] }
            .join
        {
          video_id: r["videoId"],
          title: r.dig("title", "runs", 0, "text"),
          description: snippet,
          channel_title: r.dig("ownerText", "runs", 0, "text"),
          published_at: relative_time(r.dig("publishedTimeText", "simpleText")),
          duration_seconds: clock_seconds(r.dig("lengthText", "simpleText")),
        }
      end

      # "3 weeks ago" to a date, roughly; only ever used as a hint.
      def relative_time(text)
        m = text.to_s.match(/(\d+)\s+(second|minute|hour|day|week|month|year)/i)
        return nil if m.nil?
        n = m[1].to_i
        now = Time.zone.now
        case m[2].downcase
        when "day"
          now - n.days
        when "week"
          now - n.weeks
        when "month"
          now - n.months
        when "year"
          now - n.years
        else
          now
        end
      end

      # "1:08:44" => 4124
      def clock_seconds(text)
        return nil if text.blank?
        parts = text.to_s.split(":").map(&:to_i)
        return nil if parts.empty? || parts.any?(&:negative?)
        parts.reduce(0) { |total, part| total * 60 + part }
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

      # Scraped results carry their duration; API snippets do not, and one
      # cheap videos call per page fills it in.
      def durations_for(videos)
        known = videos.to_h { |video| [video[:video_id], video[:duration_seconds]] }
        missing = known.select { |_id, seconds| seconds.nil? }.keys
        return known if missing.empty? || api_key.blank?
        params = URI.encode_www_form(part: "contentDetails", id: missing.join(","), key: api_key)
        Array(get_json("#{ENDPOINT}/videos?#{params}")["items"]).each do |entry|
          known[entry["id"]] = iso8601_seconds(entry.dig("contentDetails", "duration"))
        end
        known
      rescue Error
        known
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
        place = TitlePlace.parse(video[:title], band_name: band.name)
        date, certain = video_date(video[:title], video[:description], video[:published_at])
        {
          external_id: video[:video_id],
          ignore:
            ReleaseDetector.reason(
              title: video[:title],
              description: video[:description],
              channel: video[:channel_title],
              band_name: band.name,
              dated: ShowMatcher.extract_date(video[:title]).present?,
            ),
          url: "https://www.youtube.com/watch?v=#{video[:video_id]}",
          title: video[:title],
          date: date,
          date_certain: certain,
          venue: place[:venue],
          city: place[:city],
          region: place[:region],
          kind: "video",
          format: "video",
          taper_name: video[:channel_title],
          channel: video[:channel_title],
          published_at: video[:published_at],
          duration_seconds: duration,
        }
      end

      # A search for the band's name returns some noise; keep a video only
      # when the band is actually named in it.
      def mentions_band?(video)
        text = Venue.normalize("#{video[:title]} #{video[:description]} #{video[:channel_title]}")
        text.include?(Venue.normalize(band.name))
      end

      # The date written in the title, settled against known shows when it
      # reads two ways. A date that appears only in the description is a
      # weaker signal (release dates, "since 2019") and counts only when it
      # lands on a known show. Else a show inferred from the place named.
      # Returns the date and whether it was read straight from the title.
      def video_date(title, description, published_at)
        candidates = ShowMatcher.date_candidates(title, year_hint: published_at)
        return candidates.first, true if candidates.size == 1
        if candidates.size > 1
          return [
            candidates.find { |date| known_show_dates.include?(date) } || candidates.first,
            true
          ]
        end
        date = date_from_description(description, year_hint: published_at)
        return date, false if date
        [infer_date("#{title} #{description}", published_at), false]
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
