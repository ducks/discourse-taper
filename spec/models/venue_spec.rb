# frozen_string_literal: true

describe DiscourseTaper::Venue do
  it "normalises spellings to comparable keys" do
    n = described_class.method(:normalize)
    expect(n.call("Lockn’ Festival")).to eq("lockn festival")
    expect(n.call("Lockn' Festival")).to eq("lockn festival")
    expect(n.call("The Fillmore")).to eq("fillmore")
    expect(n.call("Barton Hall, Cornell University")).to eq("barton hall cornell university")
    expect(n.call("  ")).to eq("")
  end

  it "learns aliases and resolves them, including its own name on creation" do
    venue =
      described_class.create!(
        name: "Bethel Woods Center for the Arts",
        city: "Bethel",
        region: "NY",
      )
    expect(venue.aliases).to eq(["bethel woods center for arts"])

    venue.learn!(["Bethel Woods", "Bethel Center For The Arts", "Bethel Woods"])
    expect(venue.reload.aliases).to contain_exactly(
      "bethel woods center for arts",
      "bethel woods",
      "bethel center for arts",
    )
    expect(described_class.find_by_alias("BETHEL WOODS")).to eq(venue)
    expect(described_class.find_by_alias("Somewhere Else")).to be_nil
  end

  it "finds a typo'd spelling by trigram similarity, with a score" do
    venue = described_class.create!(name: "Saratoga Performing Arts Center")
    found, score = described_class.fuzzy("Saratoga Perfroming Arts Ctr")
    expect(found).to eq(venue)
    expect(score).to be > 0.45
    expect(described_class.fuzzy("Red Rocks")).to be_nil
    # A shared last word is not a match: the first word must agree.
    expect(described_class.fuzzy("Mann Center")).to be_nil
  end

  it "dedupes on create through aliases" do
    venue = described_class.create!(name: "Madison Square Garden")
    venue.learn!(["MSG"])
    expect(described_class.find_or_create_canonical!(name: "msg")).to eq(venue)
    expect(described_class.count).to eq(1)
    expect(described_class.find_or_create_canonical!(name: "Keystone Berkeley")).not_to eq(venue)
    expect(described_class.count).to eq(2)
  end
end
