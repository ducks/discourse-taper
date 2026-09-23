# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Walks an archive.org collection through the advancedsearch API, which
    # returns per-item venue, coverage (city), taper, lineage, and runtime
    # for most live music collections. One request per page.
    class ArchiveOrg < Base
      ENDPOINT = "https://archive.org/advancedsearch.php"
      FIELDS = %w[identifier title date venue coverage taper source lineage runtime].freeze

      def self.key
        "archive_org"
      end

      def self.available?
        true
      end

      private

      def each_item
        collection = band.archive_org_collection.presence
        return if collection.blank?

        page = 1
        loop do
          docs = fetch_page(collection, page)
          break if docs.empty?
          docs.each { |doc| yield item_from(doc) }
          break if docs.size < SiteSetting.taper_import_page_size
          page += 1
          break if page > 40 # hard stop; a collection this large gets split by year
        end
      end

      def fetch_page(collection, page)
        query = {
          q: "collection:#{collection} AND mediatype:etree",
          rows: SiteSetting.taper_import_page_size,
          page: page,
          output: "json",
          sort: ["date desc"],
        }
        params = URI.encode_www_form(query.merge("fl[]" => FIELDS))
        get_json("#{ENDPOINT}?#{params}").dig("response", "docs") || []
      end

      def item_from(doc)
        city, region = doc["coverage"].to_s.split(",", 2).map { |s| s&.strip.presence }
        lineage = [doc["source"], doc["lineage"]].compact.join(" | ").presence
        {
          external_id: doc["identifier"],
          url: "https://archive.org/details/#{doc["identifier"]}",
          title: doc["title"],
          date: doc["date"].present? ? Date.parse(doc["date"].to_s[0, 10]) : nil,
          venue: doc["venue"].presence,
          city: city,
          region: region,
          taper_name: doc["taper"].presence,
          lineage: lineage,
          duration_seconds: runtime_seconds(doc["runtime"]),
          kind: etree_kind("#{doc["identifier"]} #{doc["source"]}"),
          format: classify_format(doc["identifier"]),
        }
      rescue Date::Error
        { external_id: doc["identifier"], title: doc["title"] }
      end

      # On etree the unmarked default is an audience tape: identifiers name
      # the microphones (dpa4021, gefell, schoeps) rather than say "aud".
      def etree_kind(text)
        kind = classify_kind(text)
        kind == "unknown" ? "audience" : kind
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
