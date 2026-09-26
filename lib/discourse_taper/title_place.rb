# frozen_string_literal: true

module DiscourseTaper
  # Reads a venue, city, and region out of a recording's title, in the
  # shapes tapers and uploaders actually use. Every importer that has no
  # structured venue field goes through here.
  #
  #   "Band - 2026-08-19 - The Independent, San Francisco, CA [AUD]"
  #     => The Independent / San Francisco / CA
  #   "Band 2026-07-31 Newport Jazz Festival" => Newport Jazz Festival
  #   "Band live in Richmond at Iron Blossom Festival 9/20/26"
  #     => Iron Blossom Festival / Richmond
  #   "Band live in NYC @ le Poisson Rouge - Full set, night 1"
  #     => le Poisson Rouge / NYC
  #   "Band - Live (FULL SET) @ Underground Arts - Philadelphia, PA 9/16/26"
  #     => Underground Arts / Philadelphia / PA
  #   "Band - Edinburgh - Usher Hall - 6 September, 2026" => Usher Hall / Edinburgh
  module TitlePlace
    LABELS = /\A(live|full set|full show|full concert|full performance|complete|night \d+)\z/i
    # Titles of releases and promo, never a place.
    NOISE = /\b(album|official|teaser|trailer|lyric)\b|\bvol\.?\s*\w+/i

    def self.parse(title, band_name: nil)
      text = title.to_s.dup
      text = text.gsub(/\[[^\]]*\]|\([^)]*\)/, " ")
      if band_name.present?
        text = text.sub(Regexp.new(Regexp.escape(band_name), Regexp::IGNORECASE), " ")
      end
      text = strip_dates(text)
      text = text.gsub(/\s*[-–—|]\s*/, " - ").gsub(/\s+/, " ").strip.gsub(/\A[-\s]+|[-\s]+\z/, "")
      return {} if text.blank?

      # "… @ Venue …": what follows the at-sign is the venue, up to the
      # next separator; a city named before it ("live in NYC @ …") is kept.
      if (m = text.match(/\A(.*?)\s*@\s*(.+)\z/))
        before, after = m[1], m[2]
        place = from_segments(after)
        if place[:city].blank? && (c = before.match(/(?:live\s+)?(?:in|at)\s+(.+?)\s*(?:-\s*)?\z/i))
          place[:city] = c[1].strip
        end
        return place[:venue].to_s.match?(NOISE) ? {} : place
      end

      if (m = text.match(/\A(?:live\s+)?in\s+(.+?)\s+at\s+(.+)\z/i))
        return { venue: m[2].strip, city: m[1].strip }
      end
      if (m = text.match(/\A(?:live\s+)?at\s+(.+?)(?:\s+in\s+(.+))?\z/i))
        return { venue: m[1].strip, city: m[2]&.strip }
      end

      place = from_segments(text)
      place[:venue].to_s.match?(NOISE) ? {} : place
    end

    # Dash-separated segments: labels ("Live", "Full set") drop out, and
    # when the venue is its own segment tapers put it last and the city
    # first ("Live - Toronto ON - RBC Amphitheatre"). A segment with commas
    # is "Venue, City, Region".
    def self.from_segments(text)
      segments =
        text
          .split(/\s+-\s+/)
          .map { |s| s.gsub(/\A[-\s]+|[-\s]+\z/, "") }
          .reject { |s| s.blank? || s.match?(LABELS) }
      return {} if segments.empty?

      if segments.size > 1 && !segments.last.include?(",")
        return { venue: segments.last, city: segments.first }
      end
      if segments.size > 1 && !segments.first.include?(",")
        # "Underground Arts - Philadelphia, PA": venue first, place after.
        rest = parts_of(segments[1..].join(", "))
        return { venue: segments.first, city: rest.shift, region: rest.shift }
      end

      text = segments.find { |s| s.include?(",") } || segments.last
      return {} if text.length < 3

      parts = parts_of(text)
      { venue: parts.shift, city: parts.shift, region: parts.shift }
    end

    # Comma-separated parts with labels ("Full set", "night 1") dropped.
    def self.parts_of(text)
      text.split(/\s*,\s*/).map(&:strip).reject { |p| p.blank? || p.match?(LABELS) }
    end

    def self.strip_dates(text)
      # Day-first written dates go before month-first ones, or "24 AUG
      # 2026" loses its month and year and keeps the 24.
      text
        .gsub(/\b\d{4}[-_.\/]\d{1,2}[-_.\/]\d{1,2}\b/, " ")
        .gsub(%r{\b\d{1,2}[/.]\d{1,2}[/.]\d{2,4}\b}, " ")
        .gsub(/\b\d{1,2}(?:st|nd|rd|th)?\s+#{ShowMatcher::MONTH_PATTERN},?\s*\d{0,4}\b/i, " ")
        .gsub(/\b#{ShowMatcher::MONTH_PATTERN}\s+\d{1,2}(?:st|nd|rd|th)?,?\s*\d{0,4}\b/i, " ")
        .gsub(/[’']\d{2}\b/, " ")
    end
  end
end
