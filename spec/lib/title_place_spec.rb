# frozen_string_literal: true

describe DiscourseTaper::TitlePlace do
  def parse(title)
    described_class.parse(title, band_name: "Angine de Poitrine")
  end

  it "reads the taper's dash form, venue then place" do
    expect(
      parse("Angine de Poitrine - 2026-08-19 - The Independent, San Francisco, CA [AUD]"),
    ).to eq(venue: "The Independent", city: "San Francisco", region: "CA")
    expect(parse("Angine de Poitrine 2026-07-31 Newport Jazz Festival")).to eq(
      venue: "Newport Jazz Festival",
      city: nil,
      region: nil,
    )
  end

  it "reads city first, venue last, and drops labels" do
    expect(
      parse("Angine de Poitrine - Live - Toronto ON - July 14, 2026 - RBC Amplitheatre"),
    ).to include(venue: "RBC Amplitheatre", city: "Toronto ON")
    expect(parse("Angine de Poitrine - Edinburgh - Usher Hall - 6 September, 2026")).to include(
      venue: "Usher Hall",
      city: "Edinburgh",
    )
    expect(
      parse("Angine de Poitrine - 2026-09-01 - Live Music Hall, Cologne, Germany [AUD]"),
    ).to eq(venue: "Live Music Hall", city: "Cologne", region: "Germany")
  end

  it "reads in and at" do
    expect(parse("Angine De Poitrine live in Richmond at Iron Blossom Festival 9/20/26")).to eq(
      venue: "Iron Blossom Festival",
      city: "Richmond",
    )
    expect(parse("Angine De Poitrine Live At Electric Ballroom 11.05.2026")).to eq(
      venue: "Electric Ballroom",
      city: nil,
    )
    expect(parse("Angine de Poitrine Live at THE PEARL Vancouver 24 AUG 2026")).to eq(
      venue: "THE PEARL Vancouver",
      city: nil,
    )
  end

  it "reads the at-sign form" do
    expect(
      parse("Angine de Poitrine live in NYC @ le Poisson Rouge - Full set, night 1 - 09/09/26"),
    ).to include(venue: "le Poisson Rouge", city: "NYC")
    expect(
      parse("Angine de Poitrine - Live (FULL SET) @ Underground Arts - Philadelphia, PA 9/16/26"),
    ).to eq(venue: "Underground Arts", city: "Philadelphia", region: "PA")
    expect(
      parse("Angine de Poitrine live @ Festival de Jazz de Montréal (Québec) 2026-06-27"),
    ).to include(venue: "Festival de Jazz de Montréal")
    expect(parse("Angine de Poitrine live @Kalorama Lisbon, FULL SHOW")).to include(
      venue: "Kalorama Lisbon",
    )
  end

  it "gives nothing for a title with no place" do
    expect(parse("Angine de Poitrine - Vol.1 (Full Album)")).to eq({})
    expect(parse("Angine de Poitrine 2026-09-16")).to eq({})
  end
end
