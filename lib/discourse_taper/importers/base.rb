# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Shared plumbing for the automated channel. An importer fetches
    # structured results from a service, resolves each to a band and a
    # date, and files what it finds as suggestions. It never creates a
    # show or source itself; a person accepts them, which is what keeps
    # the archive trustworthy whether a bot or a human found the item.
    class Base
      MAX_BODY_BYTES = 4.megabytes
      USER_AGENT = "Discourse Taper (+https://github.com/ducks/discourse-taper)"

      attr_reader :band

      def initialize(band:)
        @band = band
      end

      def self.key
        raise NotImplementedError
      end

      def self.available?
        raise NotImplementedError
      end

      # Returns counts: { proposed:, matched:, skipped: }.
      def run
        stats = { proposed: 0, matched: 0, skipped: 0 }
        each_item do |item|
          outcome = propose(item)
          stats[outcome] += 1
        end
        stats
      end

      private

      def each_item
        raise NotImplementedError
      end

      # Files one item as a suggestion. Already-known external ids and
      # items with no recoverable date are skipped.
      def propose(item)
        external_id = item[:external_id]
        return :skipped if external_id.blank?
        return :skipped if Source.exists?(provider: self.class.key, external_id: external_id)
        if Suggestion
             .where(origin: self.class.key)
             .where("payload->>'external_id' = ?", external_id)
             .exists?
          return :skipped
        end

        date =
          item[:date] || ShowMatcher.extract_date(item[:title]) ||
            ShowMatcher.extract_date(external_id)
        return :skipped if date.nil?

        show = ShowMatcher.new(band: band).find(date: date, venue: item[:venue])
        source = source_payload(item, date)

        if show
          Suggestion.create!(
            kind: "new_source",
            band: band,
            show: show,
            origin: self.class.key,
            payload: source,
          )
          :matched
        else
          Suggestion.create!(
            kind: "new_show",
            band: band,
            origin: self.class.key,
            payload: {
              "date" => date.iso8601,
              "venue" => item[:venue].presence || I18n.t("taper.unknown_venue"),
              "city" => item[:city],
              "region" => item[:region],
              "source" => source,
              "external_id" => external_id,
            },
          )
          :proposed
        end
      end

      def source_payload(item, date)
        {
          "provider" => self.class.key,
          "external_id" => item[:external_id],
          "url" => item[:url],
          "title" => item[:title],
          "kind" => item[:kind] || "unknown",
          "format" => item[:format] || "unknown",
          "taper_name" => item[:taper_name],
          "lineage" => item[:lineage],
          "duration_seconds" => item[:duration_seconds],
          "date" => date.iso8601,
          "venue" => item[:venue],
        }.compact
      end

      # GET JSON through Discourse's SSRF-aware client, with a body cap.
      def get_json(url)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "application/json"

        body = +""
        FinalDestination::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 10,
          read_timeout: 20,
        ) do |http|
          http.request(request) do |response|
            raise Error.new("importer_http", status: response.code) if response.code.to_i != 200
            response.read_body do |chunk|
              body << chunk
              raise Error.new("importer_too_large") if body.bytesize > MAX_BODY_BYTES
            end
          end
        end

        JSON.parse(body)
      end

      def classify_kind(text)
        t = text.to_s.downcase
        return "soundboard" if t =~ /\bsbd\b|soundboard|board/
        return "matrix" if t =~ /matrix|\bmtx\b/
        return "audience" if t =~ /\baud\b|audience/
        "unknown"
      end

      def classify_format(text)
        t = text.to_s.downcase
        return "flac" if t.include?("flac")
        return "shn" if t =~ /\bshn/
        return "mp3" if t.include?("mp3")
        "unknown"
      end
    end
  end
end
