# frozen_string_literal: true

module DiscourseTaper
  # What the setlists say about the songs: how often each was played,
  # when first and last, where it sat in the set, and every night it
  # appeared. Built from the shows' setlists on request; nothing is
  # stored, so it is always as right as the setlists are.
  #
  # Songs are keyed by a normalised title so "Yor Zarad" and "Yor zarad"
  # are one song; the spelling seen most often is the one shown. A song
  # played from tape is not the band playing and is left out.
  class SongIndex
    Song =
      Struct.new(
        :slug,
        :title,
        :count,
        :first_date,
        :last_date,
        :opened,
        :closed,
        :encore,
        :nights,
        keyword_init: true,
      )
    Night = Struct.new(:show, :position, :of, :notes, :encore, keyword_init: true)

    def initialize(band)
      @band = band
    end

    def songs
      @songs ||= build.sort_by { |song| [-song.count, song.title] }
    end

    def find(slug)
      songs.find { |song| song.slug == slug }
    end

    def self.slug_for(title)
      Venue.normalize(title).tr(" ", "-")
    end

    private

    def build
      by_slug = {}
      spellings = Hash.new { |h, k| h[k] = Hash.new(0) }

      @band
        .shows
        .includes(:sources)
        .by_date
        .each do |show|
          setlist = show.setlist
          next if setlist.blank?
          performed = setlist.reject { |s| s["notes"].to_s.match?(/\btape\b/i) }
          performed.each_with_index do |entry, index|
            title = entry["title"].to_s.strip
            slug = self.class.slug_for(title)
            next if slug.blank?
            spellings[slug][title] += 1
            song =
              by_slug[slug] ||= Song.new(
                slug: slug,
                count: 0,
                opened: 0,
                closed: 0,
                encore: 0,
                nights: [],
              )
            encore = entry["notes"].to_s.match?(/\bencore\b|\brappel\b/i)
            song.count += 1
            song.opened += 1 if index.zero?
            song.closed += 1 if index == performed.size - 1
            song.encore += 1 if encore
            song.first_date = show.date if song.first_date.nil? || show.date < song.first_date
            song.last_date = show.date if song.last_date.nil? || show.date > song.last_date
            song.nights << Night.new(
              show: show,
              position: index + 1,
              of: performed.size,
              notes: entry["notes"],
              encore: encore,
            )
          end
        end

      by_slug.each_value do |song|
        song.title = spellings[song.slug].max_by { |_t, n| n }.first
        song.nights.sort_by! { |night| night.show.date }
      end
      by_slug.values
    end
  end
end
