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
    #
    # An item may also be show-only (no recording): setlist.fm knows the
    # date, venue, tour, and songs but has no tape. Those propose the show
    # with its setlist, or fill in the setlist of a show that lacks one.
    class Base
      MAX_BODY_BYTES = 4.megabytes
      USER_AGENT = "Discourse Taper (+https://github.com/ducks/discourse-taper)"

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

      # Returns counts:
      #   proposed  new_show suggestions created
      #   matched   new_source suggestions created for shows that exist
      #   corrected setlist corrections proposed for shows lacking one
      #   appended  recordings added to an already pending suggestion
      #   ignored   releases (albums, music videos, teasers, podcasts)
      #   accepted  recordings attached to a show outright (band opted in)
      #   skipped   items with no id, no recoverable date, or already known
      def run
        stats = {
          proposed: 0,
          matched: 0,
          corrected: 0,
          ignored: 0,
          accepted: 0,
          appended: 0,
          skipped: 0,
        }
        fresh = []

        each_item do |item|
          if item[:ignore].present?
            file_media(item)
            stats[:ignored] += 1
            next
          end
          date = resolve_date(item)
          if item[:external_id].blank? || date.nil? || known?(item)
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

      # Already attached as a source, already inside a pending suggestion's
      # recordings, or rejected once: a reviewer's no is final for an
      # importer. Show-only importers override this.
      def known?(item)
        external_id = item[:external_id]
        return true if Source.exists?(provider: self.class.key, external_id: external_id)

        Suggestion
          .where(status: %w[pending rejected])
          .where("payload->'sources' @> ?", [{ "external_id" => external_id }].to_json)
          .exists?
      end

      # Files one date's items: appended to the pending suggestion for that
      # date if there is one, whichever importer opened it (setlist.fm
      # proposes the show, YouTube adds the tape to that same row), else
      # recordings for an existing show, else a setlist for an existing
      # show that has none, else a new show.
      # Returns the stats key for what happened.
      def file_group(date, items)
        recordings = items.select { |item| item[:url].present? }
        sources = recordings.map { |item| source_payload(item, date) }
        venues = items.map { |item| item[:venue] }.compact_blank.tally
        match = VenueResolver.new.resolve(venues)
        venue = match ? match.name : majority(venues)
        show = ShowMatcher.new(band: band).find(date: date, venue: venue)
        setlist = items.map { |item| item[:setlist] }.compact_blank.max_by(&:size) || []
        tour = majority(items.map { |item| item[:tour] }.compact_blank.tally)

        pending = pending_for(date, show, kind: pending_kind(show, sources))
        if pending && sources.any?
          pending.payload["sources"] = Array(pending.payload["sources"]) + sources
          pending.save!
          return :appended
        end
        return :skipped if pending

        common = {
          "date" => date.iso8601,
          "venue" => venue.presence || I18n.t("taper.unknown_venue"),
          "venue_spellings" => venues,
          "sources" => sources,
          "external_id" => sources.first&.dig("external_id"),
        }
        common.merge!(show_identity(items))
        if match
          common["venue_match"] = {
            "id" => match.venue&.id,
            "name" => match.name,
            "method" => match.method,
            "score" => match.score,
          }
        end

        if show && sources.any?
          suggestion =
            Suggestion.create!(
              kind: "new_source",
              band: band,
              show: show,
              origin: self.class.key,
              payload: common,
            )
          if auto_accept?(items)
            SuggestionReviewer.new(reviewer: Discourse.system_user).accept!(
              suggestion,
              note: I18n.t("taper.auto_accepted"),
            )
            return :accepted
          end
          :matched
        elsif show
          return :skipped if setlist.empty? || show.setlist.any?
          Suggestion.create!(
            kind: "correction",
            band: band,
            show: show,
            origin: self.class.key,
            payload: common.merge("changes" => { "setlist" => setlist, "tour" => tour }.compact),
          )
          :corrected
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
                "country" =>
                  majority(items.map { |item| item[:country] }.compact_blank.tally) ||
                    match&.venue&.country,
                "tour" => tour,
                "setlist" => setlist,
              ),
          )
          :proposed
        end
      end

      # A release or press item goes on the band's media shelf instead of
      # the queue, keyed by provider and id so re-runs refresh it in place.
      def file_media(item)
        return if item[:external_id].blank? || item[:url].blank?
        MediaItem.file!(
          band: band,
          provider: self.class.key,
          external_id: item[:external_id],
          attributes: {
            url: item[:url],
            title: item[:title].presence || item[:external_id],
            kind: MediaItem.kind_for(item[:ignore]),
            reason: item[:ignore],
            channel: item[:channel].presence || item[:taper_name].presence,
            published_on: item[:date] || item[:published_at]&.to_date,
            duration_seconds: item[:duration_seconds],
          },
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn(
          "#{PLUGIN_NAME}: could not file media #{item[:external_id]}: #{e.message}",
        )
      end

      # A band may opt in to attaching recordings outright when every one
      # of them carries its date in its own title or identifier and that
      # date is a show the archive already has. Inferred dates, proposed
      # shows, corrections, and claims always wait for a reviewer.
      def auto_accept?(items)
        band.auto_accept_recordings && items.all? { |item| item[:date_certain] }
      end

      # The band's shows, plus shows proposed and waiting, as the places
      # an undated recording can be matched to.
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

      def known_show_dates
        @known_show_dates ||= known_shows.map { |show| show[:date] }.uniq
      end

      # A date that appears only in a description is a weaker signal
      # (release dates, "since 2019") and counts only when it lands on a
      # known show.
      def date_from_description(description, year_hint: nil)
        candidates = ShowMatcher.date_candidates(description, year_hint: year_hint)
        (candidates & known_show_dates).first
      end

      # Undated item naming a place the band played: the one show there in
      # the year the text gives, else in the month before it was published,
      # else the one show ever there. Two candidates leave it undated.
      INFERENCE_WINDOW = 31

      def infer_date(text, published_at)
        haystack = Venue.normalize(text)
        named =
          known_shows.select do |show|
            [show[:venue], show[:city]].any? { |place| mentions?(haystack, place) }
          end
        return nil if named.empty?

        if (year = year_in(text))
          date = unique_date(named.select { |show| show[:date].year == year })
          return date if date
        end
        if published_at
          window = (published_at.to_date - INFERENCE_WINDOW)..published_at.to_date
          date = unique_date(named.select { |show| window.cover?(show[:date]) })
          return date if date
        end
        unique_date(named)
      end

      def unique_date(shows)
        dates = shows.map { |show| show[:date] }.uniq
        dates.size == 1 ? dates.first : nil
      end

      # "Fuji Rock 2026", "Winnipeg Folk Fest '26".
      def year_in(text)
        if (m = text.to_s.match(/\b(19|20)(\d{2})\b/))
          return "#{m[1]}#{m[2]}".to_i
        end
        if (m = text.to_s.match(/['’](\d{2})\b/))
          return 2000 + m[1].to_i
        end
        nil
      end

      # The place is named when its whole name appears, or when every
      # distinctive word of it does ("Fuji Rock 2026" names Fuji Rock
      # Festival; "Newport Jazz Festival, 2026" names it either way).
      GENERIC_WORDS = %w[
        festival
        fest
        theatre
        theater
        hall
        club
        arena
        park
        stage
        scene
        centre
        center
        music
        live
        the
      ].freeze

      def mentions?(haystack, place)
        needle = Venue.normalize(place)
        return false if needle.length < 4
        return true if haystack.include?(needle)
        words = needle.split(/\s+/) - GENERIC_WORDS
        words.any? && words.all? { |w| w.length >= 4 && haystack.match?(/\b#{Regexp.escape(w)}\b/) }
      end

      # Service-specific identifiers an importer wants carried onto the
      # show when accepted, so it never proposes the same show twice.
      def show_identity(_items)
        {}
      end

      def pending_kind(show, sources)
        return "new_show" if show.nil?
        sources.any? ? "new_source" : "correction"
      end

      def pending_for(date, show, kind:)
        scope = Suggestion.where(status: "pending", band_id: band.id, kind: kind).reorder(nil)
        if show
          scope.find_by(show_id: show.id)
        else
          scope.find_by("payload->>'date' = ?", date.iso8601)
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

      def get_json(url, headers: {})
        JSON.parse(get_body(url, headers: headers, accept: "application/json"))
      end

      def get_html(url, headers: {})
        get_body(url, headers: headers, accept: "text/html")
      end

      def get_body(url, headers: {}, accept: "application/json")
        attempt = 0
        begin
          attempt += 1
          fetch_body(url, headers: headers, accept: accept)
        rescue *RETRYABLE => e
          raise if attempt >= RETRIES
          Rails.logger.info(
            "#{PLUGIN_NAME}: #{self.class.key} retrying after #{e.class} (attempt #{attempt} of #{RETRIES})",
          )
          sleep(attempt)
          retry
        end
      end

      # GET through Discourse's SSRF-aware client, with a body cap.
      def fetch_body(url, headers: {}, accept: "application/json")
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = accept
        headers.each { |name, value| request[name] = value }

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

        body
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
