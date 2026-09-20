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
    # identifier ("gd1977-05-08.sbd.hicks.4982.sbeok.shnf") or a YouTube
    # title ("Grateful Dead - 5/8/77 - Barton Hall"). Returns nil rather
    # than guess when nothing unambiguous is present.
    def self.extract_date(text)
      return nil if text.blank?

      if (m = text.match(/(\d{4})[-_.\/](\d{1,2})[-_.\/](\d{1,2})/))
        return safe_date(m[1].to_i, m[2].to_i, m[3].to_i)
      end

      if (m = text.match(%r{\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b}))
        year = m[3].to_i
        year += year < 100 ? (year < 40 ? 2000 : 1900) : 0
        return safe_date(year, m[1].to_i, m[2].to_i)
      end

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
