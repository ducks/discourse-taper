# frozen_string_literal: true

describe DiscourseTaper::VenueResolver do
  subject(:resolver) { described_class.new }

  it "prefers a learned alias, trying the most common spelling first" do
    venue = DiscourseTaper::Venue.create!(name: "Bethel Woods Center for the Arts")
    venue.learn!(["Bethel Woods"])

    match = resolver.resolve("Bethel Woods" => 3, "Bethel Woods Arts Center" => 1)
    expect(match).to have_attributes(venue: venue, name: venue.name, method: "alias", score: 1.0)
  end

  it "expands a standard abbreviation even before the venue exists" do
    match = resolver.resolve("MSG" => 16, "Madison Square Garden" => 3)
    expect(match).to have_attributes(
      venue: nil,
      name: "Madison Square Garden",
      method: "abbreviation",
    )

    venue = DiscourseTaper::Venue.create!(name: "Madison Square Garden")
    expect(resolver.resolve("MSG" => 1).venue).to eq(venue)
  end

  it "falls back to a trigram near-match with its score" do
    venue = DiscourseTaper::Venue.create!(name: "Saratoga Performing Arts Center")
    match = resolver.resolve("Saratoga Perfroming Arts Ctr" => 1)
    expect(match.venue).to eq(venue)
    expect(match.method).to eq("fuzzy")
    expect(match.score).to be_between(0.45, 1.0)
  end

  it "returns nil when nothing is confident" do
    DiscourseTaper::Venue.create!(name: "Barton Hall")
    DiscourseTaper::Venue.create!(name: "Saratoga Performing Arts Center")
    # Sharing one word is not a match: this bit a real import.
    expect(resolver.resolve("Mann Center" => 2, "mann ctr" => 1)).to be_nil
    expect(resolver.resolve("Old Renaissance Faire Grounds" => 2)).to be_nil
    expect(resolver.resolve({})).to be_nil
  end
end
