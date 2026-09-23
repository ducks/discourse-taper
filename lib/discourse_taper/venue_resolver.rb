# frozen_string_literal: true

module DiscourseTaper
  # Turns the spellings an importer saw for one night into a canonical
  # venue, without a model: a learned alias first, then the abbreviations
  # every taper uses, then a trigram near-match. Returns nil when nothing
  # is confident enough, and the importer falls back to majority spelling.
  class VenueResolver
    Match = Struct.new(:venue, :name, :method, :score, keyword_init: true)

    ABBREVIATIONS = {
      "msg" => "Madison Square Garden",
      "spac" => "Saratoga Performing Arts Center",
      "red rocks" => "Red Rocks Amphitheatre",
      "gorge" => "The Gorge Amphitheatre",
      "fillmore" => "The Fillmore",
      "bethel woods" => "Bethel Woods Center for the Arts",
      "deer creek" => "Deer Creek Music Center",
      "alpine" => "Alpine Valley Music Theatre",
      "alpine valley" => "Alpine Valley Music Theatre",
      "shoreline" => "Shoreline Amphitheatre",
      "gotv" => "Gathering of the Vibes",
      "hampton" => "Hampton Coliseum",
      "the mothership" => "Hampton Coliseum",
      "mothership" => "Hampton Coliseum",
    }.freeze

    # spellings: { "Spelling" => count }
    def resolve(spellings)
      ordered = spellings.to_h.sort_by { |spelling, count| [-count, -spelling.length] }.map(&:first)
      return nil if ordered.empty?

      ordered.each do |spelling|
        venue = Venue.find_by_alias(spelling)
        return Match.new(venue: venue, name: venue.name, method: "alias", score: 1.0) if venue
      end

      ordered.each do |spelling|
        full = ABBREVIATIONS[Venue.normalize(spelling)]
        next if full.nil?
        venue = Venue.find_by_alias(full)
        return(
          Match.new(venue: venue, name: venue&.name || full, method: "abbreviation", score: 1.0)
        )
      end

      ordered.each do |spelling|
        venue, score = Venue.fuzzy(spelling)
        if venue
          return Match.new(venue: venue, name: venue.name, method: "fuzzy", score: score.round(2))
        end
      end

      nil
    end
  end
end
