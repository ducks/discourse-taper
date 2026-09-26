# frozen_string_literal: true

module DiscourseTaper
  # Tells a release from a tape. Searching for a band turns up its own
  # albums, singles, music videos, teasers, and podcast appearances next
  # to the live recordings, and none of those belong in the archive.
  # Returns a short reason when an item is one of them, nil when it may
  # be a recording of a show.
  module ReleaseDetector
    PATTERNS = {
      "official video" =>
        /\b(official|officiel(le)?)\b.{0,20}\b(video|vid[ée]o|clip|audio|visuali[sz]er)\b|\bclip\s+officiel\b/i,
      "music video" => /\b(music|lyric|lyrics)\s+video\b/i,
      "teaser" => /\b(teaser|trailer|bande[- ]annonce|promo)\b/i,
      "album" =>
        /\b(full|complete|entire)\s+album\b|\balbum\s*\(?(int[ée]gral|complet|complete|full)\b|\b(int[ée]gral|complet|complete)\s+album\b|\balbum\)?\s*$/i,
      "single" => /\b(single|remix|remaster(ed)?|instrumental|acoustic version)\b/i,
      "podcast" =>
        /\b(podcast|episode|[ée]pisode)\b|#\d+\b.{0,40}\b(featuring|feat\.?|ft\.?|with)\b/i,
    }.freeze

    # A numbered volume with no date anywhere is the album, not a night.
    VOLUME = /\bvol\.?\s*(i{1,3}|iv|v|\d+)\b/i

    LIVE_CUES = /\b(live|en direct|en concert|concert|session|set|show|fest(ival)?|tour|tournée)\b/i

    # In a description, only the unmistakable patterns count: tapers write
    # "single source" and "remastered audio" about their own recordings.
    DESCRIPTION_PATTERNS =
      PATTERNS
        .slice("official video", "music video", "teaser", "album", "podcast")
        .merge("single" => /\bsingle release\b|\breleased as a single\b/i)
        .freeze

    def self.reason(title:, description: nil, channel: nil, band_name: nil, dated: false)
      PATTERNS.each { |reason, pattern| return reason if title.to_s.match?(pattern) }
      DESCRIPTION_PATTERNS.each do |reason, pattern|
        return reason if description.to_s.match?(pattern)
      end
      text = "#{title} #{description}"
      return "album" if !dated && text.match?(VOLUME)
      if channel.present? && band_name.present? && !dated &&
           Venue.normalize(channel).include?(Venue.normalize(band_name)) && !text.match?(LIVE_CUES)
        return "band's own channel, not a show"
      end
      nil
    end
  end
end
