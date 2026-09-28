# frozen_string_literal: true

describe DiscourseTaper::SongIndex do
  fab!(:category)
  fab!(:band) { Fabricate(:taper_band, name: "Angine de Poitrine") }

  def show(date, setlist)
    Fabricate(
      :taper_show,
      band: band,
      date: Date.parse(date),
      setlist: setlist,
      topic: Fabricate(:topic, category: category),
    )
  end

  it "counts every song across the setlists, keeps the common spelling, and leaves tape intros out" do
    show(
      "2026-09-16",
      [
        { "title" => "North American Scum", "notes" => "from tape, LCD Soundsystem cover" },
        { "title" => "Angor" },
        { "title" => "Yor Zarad" },
        { "title" => "Sherpa", "notes" => "closer" },
      ],
    )
    show(
      "2026-09-10",
      [
        { "title" => "Angor" },
        { "title" => "Yor zarad" },
        { "title" => "Fabienk", "notes" => "encore" },
      ],
    )
    show("2025-12-04", [{ "title" => "Sarniezz" }, { "title" => "Sherpa" }])
    show("2026-04-01", [])

    songs = described_class.new(band).songs

    expect(songs.map { |s| [s.title, s.count] }).to eq(
      [["Angor", 2], ["Sherpa", 2], ["Yor Zarad", 2], ["Fabienk", 1], ["Sarniezz", 1]],
    )
    expect(songs.map(&:title)).not_to include("North American Scum")

    angor = described_class.new(band).find("angor")
    expect(angor).to have_attributes(
      opened: 2,
      closed: 0,
      encore: 0,
      first_date: Date.new(2026, 9, 10),
      last_date: Date.new(2026, 9, 16),
    )
    expect(angor.nights.map { |n| [n.show.date.iso8601, n.position, n.of] }).to eq(
      [["2026-09-10", 1, 3], ["2026-09-16", 1, 3]],
    )

    sherpa = described_class.new(band).find("sherpa")
    expect(sherpa).to have_attributes(closed: 2, opened: 0)
    expect(described_class.new(band).find("fabienk").encore).to eq(1)
    expect(described_class.new(band).find("nope")).to be_nil
  end
end
