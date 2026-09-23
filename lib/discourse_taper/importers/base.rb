# frozen_string_literal: true

module DiscourseTaper
  module Importers
    # Shared plumbing for the automated channel. An importer fetches
    # structured results from a service, resolves each to a band and a
    # date, and files what it finds as suggestions. It never creates a
    # show or source itself; a person accepts them, which is what keeps
    # the archive trustworthy whether a bot or a human found the item.
    #
    # Everything found for one date is filed as ONE suggestion carrying
    # every recording. A real archive.org collection has five recordings
    # per night on average and a dozen spellings of each venue, so
    # proposing per item would flood the queue with duplicates of the
    # same show. Re-runs append newly found recordings to the pending
    # suggestion for that date rather than proposing it again.
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

      # Returns counts: { proposed:, matched:, appended:, skipped: }.
      #   proposed  new_show suggestions created
      #   matched   new_source suggestions created for shows that exist
      #   appended  recordings added to an already pending suggestion
      #   skipped   items with no id, no recoverable date, or already known
      def run
        stats = { proposed: 0, matched: 0, appended: 0, skipped: 0 }
        fresh = []

        each_item do |item|
          date = resolve_date(item)
          if item[:external_id].blank? || date.nil? || known?(item[:external_id])
            stats[:skipped] += 1
            next
          end
          fresh << item.merge(date: date)
        end

        fresh
          .group_by { |item| item[:date] }
          .each { |date, items| stats[file_group(date, items)] += 1 }

        stats
      end

      private

      def each_item
        raise NotImplementedError
      end

      def resolve_date(item)
        item[:date] || ShowMatcher.extract_date(item[:title]) ||
          ShowMatcher.extract_date(item[:external_id])
      end

      # Already attached as a source, or already inside a pending
      # suggestion's recordings.
      def known?(external_id)
        return true if Source.exists?(provider: self.class.key, external_id: external_id)

        Suggestion
          .where(origin: self.class.key, status: "pending")
          .where("payload->'sources' @> ?", [{ "external_id" => external_id }].to_json)
          .exists?
      end

      # Files one date's recordings: appended to the pending suggestion
      # for that date if there is one, else a new_source for an existing
      # show, else a new_show. Returns the stats key for what happened.
      def file_group(date, items)
        sources = items.map { |item| source_payload(item, date) }
        venues = items.map { |item| item[:venue] }.compact_blank.tally
        match = VenueResolver.new.resolve(venues)
        venue = match ? match.name : majority(venues)
        show = ShowMatcher.new(band: band).find(date: date, venue: venue)

        pending = pending_for(date, show)
        if pending
          pending.payload["sources"] = pending.payload["sources"] + sources
          pending.save!
          return :appended
        end

        common = {
          "date" => date.iso8601,
          "venue" => venue.presence || I18n.t("taper.unknown_venue"),
          "venue_spellings" => venues,
          "sources" => sources,
          "external_id" => sources.first["external_id"],
        }
        if match
          common["venue_match"] = {
            "id" => match.venue&.id,
            "name" => match.name,
            "method" => match.method,
            "score" => match.score,
          }
        end

        if show
          Suggestion.create!(
            kind: "new_source",
            band: band,
            show: show,
            origin: self.class.key,
            payload: common,
          )
          :matched
        else
          Suggestion.create!(
            kind: "new_show",
            band: band,
            origin: self.class.key,
            payload:
              common.merge(
                "city" =>
                  majority(items.map { |item| item[:city] }.compact_blank.tally) ||
                    match&.venue&.city,
                "region" =>
                  majority(items.map { |item| item[:region] }.compact_blank.tally) ||
                    match&.venue&.region,
              ),
          )
          :proposed
        end
      end

      def pending_for(date, show)
        scope =
          Suggestion.where(origin: self.class.key, status: "pending", band_id: band.id).reorder(nil)
        if show
          scope.find_by(kind: "new_source", show_id: show.id)
        else
          scope.where(kind: "new_show").find_by("payload->>'date' = ?", date.iso8601)
        end
      end

      # Most common spelling; the longer one on a tie, since "Madison
      # Square Garden" beats "MSG" when nothing else separates them.
      def majority(tally)
        return nil if tally.blank?
        tally.max_by { |value, count| [count, value.length] }.first
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

      # Transient network faults (a DNS lookup timing out, a dropped
      # connection) are common across a long paged walk. Retry a page a
      # few times before giving up on the run, so one hiccup does not
      # discard everything gathered so far.
      RETRYABLE = [
        Timeout::Error,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        SocketError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        OpenSSL::SSL::SSLError,
      ].freeze
      RETRIES = 3

      def get_json(url)
        attempt = 0
        begin
          attempt += 1
          fetch_json(url)
        rescue *RETRYABLE => e
          raise if attempt >= RETRIES
          Rails.logger.info(
            "#{PLUGIN_NAME}: #{self.class.key} retrying after #{e.class} (attempt #{attempt} of #{RETRIES})",
          )
          sleep(attempt)
          retry
        end
      end

      # GET JSON through Discourse's SSRF-aware client, with a body cap.
      def fetch_json(url)
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
