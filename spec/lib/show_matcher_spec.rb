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

  it "reads day-first, written, and French dates" do
    expect(described_class.extract_date("Angine de Poitrine 16/09/2026 Philly")).to eq(
      Date.new(2026, 9, 16),
    )
    expect(described_class.extract_date("Angine de Poitrine 16.09.26 Philly")).to eq(
      Date.new(2026, 9, 16),
    )
    expect(described_class.extract_date("Live At Electric Ballroom 11.05.2026")).to eq(
      Date.new(2026, 5, 11),
    )
    expect(described_class.extract_date("Underground Arts 9/16/26")).to eq(Date.new(2026, 9, 16))
    expect(described_class.extract_date("Full set, Underground Arts, September 16th, 2026")).to eq(
      Date.new(2026, 9, 16),
    )
    expect(described_class.extract_date("Sept 16 2026 full show")).to eq(Date.new(2026, 9, 16))
    expect(described_class.extract_date("16 September 2026")).to eq(Date.new(2026, 9, 16))
    expect(described_class.extract_date("Angine de Poitrine au Club Soda, 1er août 2026")).to eq(
      Date.new(2026, 8, 1),
    )
    expect(described_class.extract_date("16 sept. 2026 Montréal")).to eq(Date.new(2026, 9, 16))
    expect(described_class.extract_date("Live in Montréal, 24 décembre")).to be_nil
  end

  it "offers both readings of an ambiguous slash date, month first" do
    expect(described_class.date_candidates("Leeds 10/05/2026")).to eq(
      [Date.new(2026, 10, 5), Date.new(2026, 5, 10)],
    )
    expect(described_class.date_candidates("Philly 9/16/26")).to eq([Date.new(2026, 9, 16)])
    expect(described_class.date_candidates("Cologne 2026-09-01")).to eq([Date.new(2026, 9, 1)])
    expect(described_class.date_candidates("no date here")).to eq([])
  end

  it "resolves a month and day without a year against a publish date" do
    hint = Date.new(2026, 9, 20)
    expect(described_class.extract_date("Live at LPR, September 10th", year_hint: hint)).to eq(
      Date.new(2026, 9, 10),
    )
    expect(described_class.extract_date("Live at LPR, December 10th", year_hint: hint)).to eq(
      Date.new(2025, 12, 10),
    )
    expect(described_class.extract_date("Live at LPR", year_hint: hint)).to be_nil
  end
end
