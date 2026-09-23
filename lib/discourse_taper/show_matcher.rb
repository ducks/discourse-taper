# frozen_string_literal: true

module DiscourseTaper
  # Resolves "a band, a date, and maybe a venue" to an existing show. This
  # is what lets an importer hit and a taper's upload for the same night
  # land on the same record. Date is authoritative; venue only breaks ties
  # between multiple shows on one date, and is compared loosely because
  # every service spells venues differently.
  class ShowMatcher
    def initialize(band:)
      @band = band
    end

    def find(date:, venue: nil)
      candidates = Show.where(band_id: @band.id, date: date).order(:sequence).to_a
      return nil if candidates.empty?
      return candidates.first if candidates.size == 1 || venue.blank?

      wanted = normalize(venue)
      candidates.find { |show| normalize(show.venue) == wanted } ||
        candidates.find do |show|
          normalize(show.venue).include?(wanted) || wanted.include?(normalize(show.venue))
        end || candidates.first
    end

    # Best-effort date extraction from free text such as an archive.org
    # identifier ("gd1977-05-08.sbd.hicks.4982.sbeok.shnf"), a YouTube
    # title ("Grateful Dead - 5/8/77 - Barton Hall", "16/09/2026 Philly",
    # "September 16th, 2026", "16 septembre 2026"). Returns nil rather than
    # guess when nothing unambiguous is present. A month and day with no
    # year is accepted only with a year_hint (the date the text was
    # published), and lands on the most recent such day at or before it.
    MONTHS = {
      "jan" => 1,
      "january" => 1,
      "janv" => 1,
      "janvier" => 1,
      "feb" => 2,
      "february" => 2,
      "fev" => 2,
      "fevr" => 2,
      "fevrier" => 2,
      "mar" => 3,
      "march" => 3,
      "mars" => 3,
      "apr" => 4,
      "april" => 4,
      "avr" => 4,
      "avril" => 4,
      "may" => 5,
      "mai" => 5,
      "jun" => 6,
      "june" => 6,
      "juin" => 6,
      "jul" => 7,
      "july" => 7,
      "juil" => 7,
      "juillet" => 7,
      "aug" => 8,
      "august" => 8,
      "aout" => 8,
      "sep" => 9,
      "sept" => 9,
      "september" => 9,
      "septembre" => 9,
      "oct" => 10,
      "october" => 10,
      "octobre" => 10,
      "nov" => 11,
      "november" => 11,
      "novembre" => 11,
      "dec" => 12,
      "december" => 12,
      "decembre" => 12,
    }.freeze
    MONTH_PATTERN = /(#{MONTHS.keys.sort_by { |k| -k.length }.join("|")})\.?/i
    ORDINAL = /(?:st|nd|rd|th|er|e)?/

    def self.extract_date(text, year_hint: nil)
      return nil if text.blank?
      text = text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "")

      if (m = text.match(/(\d{4})[-_.\/](\d{1,2})[-_.\/](\d{1,2})/))
        return safe_date(m[1].to_i, m[2].to_i, m[3].to_i)
      end

      # 5/8/77 or 16/09/2026: month first unless the first number cannot
      # be a month.
      if (m = text.match(%r{\b(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})\b}))
        year = expand_year(m[3].to_i)
        a, b = m[1].to_i, m[2].to_i
        return a > 12 ? safe_date(year, b, a) : safe_date(year, a, b)
      end

      # September 16th, 2026 / Sept 16 2026 / 16 September 2026 / 16 sept. 2026
      if (m = text.match(/\b#{MONTH_PATTERN}\s+(\d{1,2})#{ORDINAL},?\s+(\d{4})\b/i))
        return safe_date(m[3].to_i, MONTHS[m[1].downcase], m[2].to_i)
      end
      if (m = text.match(/\b(\d{1,2})#{ORDINAL}\s+(?:of\s+)?#{MONTH_PATTERN},?\s+(\d{4})\b/i))
        return safe_date(m[3].to_i, MONTHS[m[2].downcase], m[1].to_i)
      end

      return nil if year_hint.nil?
      hint = year_hint.to_date
      if (m = text.match(/\b#{MONTH_PATTERN}\s+(\d{1,2})#{ORDINAL}\b(?!\s*[,\/.-]?\s*\d)/i))
        return nearest_before(hint, MONTHS[m[1].downcase], m[2].to_i)
      end
      if (m = text.match(/\b(\d{1,2})#{ORDINAL}\s+(?:of\s+)?#{MONTH_PATTERN}\b(?!\s*,?\s*\d)/i))
        return nearest_before(hint, MONTHS[m[2].downcase], m[1].to_i)
      end

      nil
    end

    def self.expand_year(year)
      return year if year >= 100
      year + (year < 40 ? 2000 : 1900)
    end

    def self.nearest_before(hint, month, day)
      date = safe_date(hint.year, month, day)
      return nil if date.nil?
      date > hint ? safe_date(hint.year - 1, month, day) : date
    end

    def self.safe_iso(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def self.safe_date(year, month, day)
      Date.new(year, month, day)
    rescue Date::Error
      nil
    end

    private

    def normalize(value)
      value.to_s.downcase.gsub(/\bthe\b/, "").gsub(/[^a-z0-9]+/, " ").strip
    end
  end
end
