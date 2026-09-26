# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Walks a band's setlists on setlist.fm. It knows the date, venue,
    # city, country, tour, and songs of every show fans have logged, and
    # nothing about recordings, so its items are show-only: they propose
    # new shows complete with setlists, or fill in the setlist of a show
    # that a recording importer created first. Needs a free API key.
    class SetlistFm < Base
      ENDPOINT = "https://api.setlist.fm/rest/1.0/search/setlists"
      MAX_PAGES = 60

      def self.key
        "setlist_fm"
      end

      def self.available?
        SiteSetting.taper_setlistfm_api_key.present?
      end

      private

      def each_item
        artist = band.setlistfm_artist_name.presence || band.name
        return if artist.blank? || !self.class.available?

        page = 1
        loop do
          data = fetch_page(artist, page)
          setlists = Array(data["setlist"])
          break if setlists.empty?
          setlists.each { |setlist| yield item_from(setlist) }

          per_page = data["itemsPerPage"].to_i
          total = data["total"].to_i
          break if per_page.zero? || page * per_page >= total || page >= MAX_PAGES
          page += 1
        end
      end

      def fetch_page(artist, page)
        params = URI.encode_www_form(artistName: artist, p: page)
        get_json(
          "#{ENDPOINT}?#{params}",
          headers: {
            "x-api-key" => SiteSetting.taper_setlistfm_api_key,
          },
        )
      end

      def item_from(setlist)
        venue = setlist["venue"] || {}
        city = venue["city"] || {}
        {
          external_id: setlist["id"],
          setlistfm_id: setlist["id"],
          date: parse_event_date(setlist["eventDate"]),
          venue: venue["name"].presence,
          city: city["name"].presence,
          region: city["stateCode"].presence || city["state"].presence,
          country: city.dig("country", "name").presence,
          tour: setlist.dig("tour", "name").presence,
          setlist: songs_from(setlist),
          title: "#{band.name} #{setlist["eventDate"]} #{venue["name"]}",
        }
      end

      # setlist.fm dates are dd-MM-yyyy, unambiguously.
      def parse_event_date(value)
        Date.strptime(value.to_s, "%d-%m-%Y")
      rescue Date::Error
        nil
      end

      # Flattens sets into the archive's ordered list. Set names and encores
      # become notes on the first song of each; a song marked as tape is the
      # intro or walk-on music, kept and noted since tapers care.
      def songs_from(setlist)
        sets = setlist.dig("sets", "set") || setlist["set"] || []
        songs = []
        Array(sets).each do |set|
          heading = set["encore"] ? "encore" : set["name"].presence
          Array(set["song"]).each_with_index do |song, index|
            next if song["name"].blank?
            notes = []
            notes << heading if heading && index.zero?
            notes << "from tape" if song["tape"]
            notes << "#{song.dig("cover", "name")} cover" if song.dig("cover", "name").present?
            notes << "with #{song.dig("with", "name")}" if song.dig("with", "name").present?
            notes << song["info"] if song["info"].present?
            entry = { "title" => song["name"] }
            entry["notes"] = notes.join(", ") if notes.any?
            songs << entry
          end
        end
        songs
      end

      # A show already imported from setlist.fm, or already pending, is
      # known by its setlist id rather than by a recording.
      def known?(item)
        id = item[:setlistfm_id]
        return true if Show.exists?(setlistfm_id: id)
        Suggestion
          .where(origin: self.class.key, status: %w[pending rejected])
          .where("payload->>'setlistfm_id' = ?", id)
          .exists?
      end

      def show_identity(items)
        { "setlistfm_id" => items.map { |item| item[:setlistfm_id] }.compact.first }
      end
    end
  end
end
