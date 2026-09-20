# frozen_string_literal: true

describe DiscourseTaper::ShowMatcher do
  fab!(:band, :taper_band)

  it "matches a single show on a date regardless of venue spelling" do
    show = Fabricate(:taper_show, band: band, venue: "Barton Hall")
    matcher = described_class.new(band: band)

    expect(matcher.find(date: Date.new(1977, 5, 8))).to eq(show)
    expect(
      matcher.find(date: Date.new(1977, 5, 8), venue: "Barton Hall, Cornell University"),
    ).to eq(show)
    expect(matcher.find(date: Date.new(1977, 5, 9))).to be_nil
  end

  it "breaks a two-show date by venue, falling back to the first" do
    early = Fabricate(:taper_show, band: band, sequence: 1, venue: "The Fillmore")
    late = Fabricate(:taper_show, band: band, sequence: 2, venue: "Winterland")
    matcher = described_class.new(band: band)

    expect(matcher.find(date: early.date, venue: "Winterland Arena")).to eq(late)
    expect(matcher.find(date: early.date, venue: "Fillmore")).to eq(early)
    expect(matcher.find(date: early.date, venue: "Somewhere Else")).to eq(early)
  end

  it "extracts dates from identifiers and titles" do
    expect(described_class.extract_date("gd1977-05-08.sbd.hicks.4982.sbeok.shnf")).to eq(
      Date.new(1977, 5, 8),
    )
    expect(described_class.extract_date("Grateful Dead - 5/8/77 - Barton Hall")).to eq(
      Date.new(1977, 5, 8),
    )
    expect(described_class.extract_date("Phish 2023.12.31 MSG")).to eq(Date.new(2023, 12, 31))
    expect(described_class.extract_date("Live in Ithaca")).to be_nil
    expect(described_class.extract_date("1977-13-40 nonsense")).to be_nil
  end
end
