# frozen_string_literal: true

describe DiscourseTaper::ReleaseDetector do
  def reason(title, **opts)
    described_class.reason(title: title, band_name: "Angine de Poitrine", **opts)
  end

  it "knows the band's own releases and promo from their titles" do
    expect(reason("Angine De Poitrine - Sherpa (Official CEM Video)")).to eq("official video")
    expect(reason("Angine De Poitrine - Sahardnieh (Official CEM Video)")).to eq("official video")
    expect(reason("Angine de Poitrine - Sherpa (Clip officiel)")).to eq("official video")
    expect(reason("Angine De Poitrine - Vol. 1 Teaser")).to eq("teaser")
    expect(reason("Angine de Poitrine - Vol.1 (Full Album)")).to eq("album")
    expect(reason("Angine de Poitrine - Vol.II (Album intégral)")).to eq("album")
    expect(reason("Angine de Poitrine - Vol.II (Official Complete Album)")).to eq(
      "official video",
    ).or eq("album")
    expect(reason("Angine de Poitrine - Vol. II (2026)")).to eq("album")
    expect(reason("Vol.1")).to eq("album")
    expect(reason("No Words Music #88: Dynamic Duos Part 2 Featuring Angine de Poitrine")).to eq(
      "podcast",
    )
    expect(reason("Angine de Poitrine - Yor Zarad (Remix)")).to eq("single")
  end

  it "treats an undated upload on the band's own channel with no live cue as a release" do
    expect(reason("Angine de Poitrine - Sarniezz", channel: "Angine de Poitrine")).to eq(
      "band's own channel, not a show",
    )
    expect(
      reason("Angine de Poitrine - Tamebsz", channel: "Angine de Poitrine and Spectacles Bonzai"),
    ).to eq("band's own channel, not a show")
  end

  it "lets live recordings through, dated or not, on any channel" do
    expect(
      reason("Angine de Poitrine - Full Performance (Live on KEXP)", channel: "KEXP"),
    ).to be_nil
    expect(
      reason("Angine de Poitrine - 2026-08-19 - The Independent, San Francisco, CA [AUD]"),
    ).to be_nil
    expect(
      reason("SESSION SECRÈTE IV – ANGINE DE POITRINE (2025)", channel: "Culture Sauvage"),
    ).to be_nil
    expect(
      reason("Angine de Poitrine live in NYC @ le Poisson Rouge - Full set, night 1"),
    ).to be_nil
    expect(
      reason("Angine de Poitrine - Sherpa (Live at Massey Hall)", channel: "Angine de Poitrine"),
    ).to be_nil
    expect(reason("Angine de Poitrine - Vol.II tour - Cologne 2026-09-01", dated: true)).to be_nil
    expect(
      reason(
        "ANGINE DE POITRINE en direct du Planète Claire",
        channel: "Journée de l'album québécois",
      ),
    ).to be_nil
  end
end
