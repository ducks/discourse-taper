# frozen_string_literal: true

describe DiscourseTaper::ShowsController do
  fab!(:category)
  fab!(:group)
  fab!(:private_category) { Fabricate(:private_category, group: group) }
  fab!(:member, :user)
  fab!(:band) { Fabricate(:taper_band, name: "Grateful Dead") }
  fab!(:show) do
    Fabricate(
      :taper_show,
      band: band,
      topic: Fabricate(:topic, category: category),
      setlist: [{ "title" => "Scarlet Begonias" }, { "title" => "Fire on the Mountain" }],
    )
  end
  fab!(:source) do
    Fabricate(
      :taper_source,
      show: show,
      provider: "archive_org",
      external_id: "gd77",
      kind: "soundboard",
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
  end

  it "lists bands with show counts" do
    get "/taper/bands.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["bands"].first).to include(
      "slug" => "grateful-dead",
      "show_count" => 1,
    )
  end

  it "lists a band's shows with year facets, at the short url for the primary band" do
    get "/taper.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["band"]).to include("slug" => "grateful-dead", "primary" => true)

    get "/taper/grateful-dead.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["years"]).to eq([{ "year" => 1977, "count" => 1 }])
    expect(response.parsed_body["shows"].first).to include(
      "label" => "1977-05-08",
      "source_count" => 1,
    )

    get "/taper/grateful-dead.json?year=1999"
    expect(response.parsed_body["shows"]).to eq([])
  end

  it "shows one show with setlist and sources, at both url forms" do
    get "/taper/1977-05-08.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["show"]["url"]).to eq("/taper/1977-05-08")

    get "/taper/grateful-dead/1977-05-08.json"
    expect(response.status).to eq(200)
    json = response.parsed_body["show"]
    expect(json["setlist"].map { |s| s["title"] }).to eq(
      ["Scarlet Begonias", "Fire on the Mountain"],
    )
    expect(json["sources"].first).to include("kind" => "soundboard", "provider" => "archive_org")
    expect(json["topic_url"]).to eq(show.topic.relative_url)
  end

  it "serves a non-primary band only under its slug" do
    side = Fabricate(:taper_band, name: "Jerry Garcia Band")
    Fabricate(
      :taper_show,
      band: side,
      date: Date.new(1978, 3, 1),
      topic: Fabricate(:topic, category: category),
      venue: "Keystone",
      city: nil,
      region: nil,
    )

    get "/taper/jerry-garcia-band/1978-03-01.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["show"]).to include(
      "url" => "/taper/jerry-garcia-band/1978-03-01",
      "title" => "Jerry Garcia Band 1978-03-01 Keystone",
    )
    expect(response.parsed_body["show"]["band"]).to include("primary" => false)

    get "/taper/1978-03-01.json"
    expect(response.status).to eq(404)
  end

  it "exposes the show on the topic payload" do
    get "/t/#{show.topic_id}.json"
    expect(response.parsed_body["taper_show"]["label"]).to eq("1977-05-08")
  end

  it "hides the archive when the category is private" do
    SiteSetting.taper_category_id = private_category.id
    get "/taper/bands.json"
    expect(response.status).to eq(404)

    group.add(member)
    sign_in(member)
    get "/taper/bands.json"
    expect(response.status).to eq(200)
  end

  it "lets a member suggest a correction and a new source" do
    sign_in(member)
    post "/taper/grateful-dead/suggest.json",
         params: {
           kind: "correction",
           date: "1977-05-08",
           payload: {
             changes: {
               venue: "Barton Hall, Cornell",
             },
           },
           note: "official name",
         }
    expect(response.status).to eq(200)
    expect(DiscourseTaper::Suggestion.last).to have_attributes(
      kind: "correction",
      show: show,
      submitted_by: member,
      note: "official name",
    )

    post "/taper/grateful-dead/suggest.json",
         params: {
           kind: "new_source",
           date: "1977-05-08",
           payload: {
             url: "https://www.youtube.com/watch?v=xyz",
             provider: "youtube",
           },
         }
    expect(response.status).to eq(200)
    expect(DiscourseTaper::Suggestion.last.show).to eq(show)
  end

  it "requires login to suggest" do
    post "/taper/grateful-dead/suggest.json",
         params: {
           kind: "new_show",
           payload: {
             date: "1977-05-08",
             venue: "X",
           },
         }
    expect(response.status).to eq(403)
  end
end
