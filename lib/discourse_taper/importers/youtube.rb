# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Lists a channel's uploads through the YouTube Data API. YouTube has
    # no structured venue or date, so both are recovered from the title
    # and description; anything without a recognisable date is skipped.
    class Youtube < Base
      ENDPOINT = "https://www.googleapis.com/youtube/v3"

      def self.key
        "youtube"
      end

      def self.available?
        SiteSetting.taper_youtube_api_key.present?
      end

      private

      def each_item
        channel = band.youtube_channel_id.presence
        return if channel.blank? || !self.class.available?

        playlist = uploads_playlist(channel)
        return if playlist.blank?

        token = nil
        pages = 0
        loop do
          data = fetch_playlist_page(playlist, token)
          Array(data["items"]).each { |entry| yield item_from(entry) }
          token = data["nextPageToken"]
          pages += 1
          break if token.blank? || pages >= 20
        end
      end

      def uploads_playlist(channel)
        params =
          URI.encode_www_form(
            part: "contentDetails",
            id: channel,
            key: SiteSetting.taper_youtube_api_key,
          )
        get_json("#{ENDPOINT}/channels?#{params}").dig(
          "items",
          0,
          "contentDetails",
          "relatedPlaylists",
          "uploads",
        )
      end

      def fetch_playlist_page(playlist, token)
        params = {
          part: "snippet",
          playlistId: playlist,
          maxResults: [SiteSetting.taper_import_page_size, 50].min,
          key: SiteSetting.taper_youtube_api_key,
        }
        params[:pageToken] = token if token
        get_json("#{ENDPOINT}/playlistItems?#{URI.encode_www_form(params)}")
      end

      def item_from(entry)
        snippet = entry["snippet"] || {}
        video_id = snippet.dig("resourceId", "videoId")
        text = "#{snippet["title"]} #{snippet["description"]}"
        {
          external_id: video_id,
          url: video_id && "https://www.youtube.com/watch?v=#{video_id}",
          title: snippet["title"],
          date: ShowMatcher.extract_date(text),
          venue: venue_from(snippet["title"]),
          kind: "video",
          format: "video",
        }
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
    end
  end
end
