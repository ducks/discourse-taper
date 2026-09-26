# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Walks archive.org through the advancedsearch API, one request per
    # page. A band with an etree collection is walked by collection, where
    # items carry venue, coverage (city), taper, lineage, and runtime. A
    # band without one is found by a query (creator or title) across the
    # community audio and video collections, where tapers name the venue
    # in the title instead: "Band - 2026-08-19 - The Independent, San
    # Francisco, CA [AUD]".
    class ArchiveOrg < Base
      ENDPOINT = "https://archive.org/advancedsearch.php"
      FIELDS = %w[
        identifier
        title
        date
        venue
        coverage
        taper
        source
        lineage
        runtime
        mediatype
        format
      ].freeze

      def self.key
        "archive_org"
      end

      def self.available?
        true
      end

      private

      def each_item
        query = search_query
        return if query.blank?

        page = 1
        loop do
          docs = fetch_page(query, page)
          break if docs.empty?
          docs.each { |doc| yield item_from(doc) }
          break if docs.size < SiteSetting.taper_import_page_size
          page += 1
          break if page > 40 # hard stop; a collection this large gets split by year
        end
      end

      def search_query
        if band.archive_org_collection.present?
          "collection:#{band.archive_org_collection} AND mediatype:etree"
        elsif band.archive_org_query.present?
          "(#{band.archive_org_query}) AND mediatype:(etree OR audio OR movies)"
        end
      end

      def fetch_page(query, page)
        params = {
          q: query,
          rows: SiteSetting.taper_import_page_size,
          page: page,
          output: "json",
          sort: ["date desc"],
        }
        params = URI.encode_www_form(params.merge("fl[]" => FIELDS))
        get_json("#{ENDPOINT}?#{params}").dig("response", "docs") || []
      end

      def item_from(doc)
        identifier = doc["identifier"]
        title = doc["title"].to_s
        video = doc["mediatype"] == "movies" || title.match?(/\[(vid|webcast)\]|\bwebcast\b/i)
        lineage = [doc["source"], doc["lineage"]].flatten.compact.join(" | ").presence
        place = place_from(doc)
        dated = ShowMatcher.extract_date("#{identifier} #{title}").present?
        {
          external_id: identifier,
          ignore:
            ReleaseDetector.reason(
              title: title,
              description: doc["description"],
              channel: doc["creator"],
              band_name: band.name,
              dated: dated,
            ),
          url: "https://archive.org/details/#{identifier}",
          title: doc["title"],
          # A date written into the identifier or title is the show; the
          # item's date field can be the upload date on community uploads.
          date: ShowMatcher.extract_date("#{identifier} #{title}") || field_date(doc["date"]),
          venue: place[:venue],
          city: place[:city],
          region: place[:region],
          taper_name: doc["taper"].presence,
          lineage: lineage,
          duration_seconds: runtime_seconds(doc["runtime"]),
          kind: video ? "video" : etree_kind("#{identifier} #{doc["source"]} #{title}"),
          format: video ? "video" : archive_format(doc["format"], identifier),
        }
      end

      def field_date(value)
        return nil if value.blank?
        Date.parse(value.to_s[0, 10])
      rescue Date::Error
        nil
      end

      # Venue, city, and region: from the item's own fields when it has
      # them (etree collections do), else read out of the title.
      def place_from(doc)
        if doc["venue"].present?
          city, region = doc["coverage"].to_s.split(",", 2).map { |s| s&.strip.presence }
          return { venue: doc["venue"], city: city, region: region }
        end
        TitlePlace.parse(doc["title"], band_name: band.name)
      end

      # On etree the unmarked default is an audience tape: identifiers name
      # the microphones (dpa4021, gefell, schoeps) rather than say "aud".
      def etree_kind(text)
        kind = classify_kind(text)
        kind == "unknown" ? "audience" : kind
      end

      # archive.org lists every derived file format on the item; the
      # lossless one, when present, is what a taper uploaded.
      def archive_format(formats, identifier)
        list = Array(formats).map(&:to_s).map(&:downcase)
        return "flac" if list.any? { |f| f.include?("flac") }
        return "shn" if list.any? { |f| f.include?("shorten") }
        return "mp3" if list.any? { |f| f.include?("mp3") }
        classify_format(identifier)
      end

      def runtime_seconds(value)
        return nil if value.blank?
        parts = value.to_s.split(":").map(&:to_f)
        return nil if parts.empty?
        parts.reduce(0) { |total, part| total * 60 + part }.round
      end
    end
  end
end
