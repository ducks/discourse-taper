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

  describe "reader surface" do
    it "renders the front door as html without the app: spines, latest shows, new recordings" do
      band.update!(footer: "Anonymous by design.\n\nTaped it? Claim it.")
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(1979, 1, 1),
        venue: "Oakland Auditorium",
        topic: Fabricate(:topic, category: category),
      )

      get "/taper"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("1977-05-08")
      expect(response.body).to include("Barton Hall")
      expect(response.body).to include(%(href="/taper?year=1977"))
      expect(response.body).to include(%(href="/taper?year=1979"))
      expect(response.body).to include("1978</span><span class=\"taper-spine__count\">none")
      expect(response.body).to include("2 shows")
      expect(response.body).to include("Latest shows")
      expect(response.body).to include("taper-tape__title")
      expect(response.body).to include("Taped it? Claim it.")
      expect(response.body).not_to include("discourse-data-preloaded")
    end

    it "renders a year as a month-grouped listing" do
      get "/taper", params: { year: 1977 }

      expect(response.status).to eq(200)
      expect(response.body).to include("taper-yearhead__year")
      expect(response.body).to include("May")
      expect(response.body).to include("05-08")
      expect(response.body).to include(%(href="/taper?year=1977" aria-current="true"))
      expect(response.body).to include("1 venue")
    end

    it "renders a show page with setlist, sources, neighbours, and structured data" do
      later =
        Fabricate(
          :taper_show,
          band: band,
          date: Date.new(1977, 5, 9),
          venue: "Buffalo",
          topic: Fabricate(:topic, category: category),
        )

      Fabricate(
        :taper_source,
        show: show,
        provider: "youtube",
        external_id: "Wk_PLQuICx8",
        url: "https://www.youtube.com/watch?v=Wk_PLQuICx8",
        kind: "video",
        format: "video",
        duration_seconds: 4500,
        created_at: 1.day.ago,
      )
      Fabricate(:post, topic: show.topic, raw: "The show card lives above this post.")
      Fabricate(
        :post,
        topic: show.topic,
        raw: "The intro tape is North American Scum, same as Chicago.",
      )

      get "/taper/1977-05-08"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Scarlet Begonias")
      expect(response.body).to include("SBD")
      expect(response.body).to include(%(rel="canonical"))
      expect(response.body).to include("MusicEvent")
      expect(response.body).to include(later.url)
      expect(response.body).to include(show.topic.url)
      expect(response.body).to include("https://www.youtube-nocookie.com/embed/Wk_PLQuICx8")
      expect(response.body).to include("1h 15m")
      expect(response.body).to include("The intro tape is North American Scum")
      expect(response.body).to include("1 reply")
    end

    it "caches anonymous readers and never signed-in ones" do
      get "/taper/1977-05-08"
      expect(response.headers["Cache-Control"]).to eq("max-age=60, public")

      sign_in(member)
      get "/taper/1977-05-08"
      expect(response.headers["Cache-Control"]).to eq("private, no-store")
    end

    it "404s a show the reader cannot see" do
      SiteSetting.taper_category_id = private_category.id
      get "/taper/1977-05-08"
      expect(response.status).to eq(404)
    end
  end

  describe "suggestion form" do
    it "asks anonymous readers to log in and shows the forms to members" do
      get "/taper/suggest?date=1977-05-08"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Log in")
      expect(response.body).not_to include(%(name="kind" value="new_source"))

      sign_in(member)
      get "/taper/suggest?date=1977-05-08"
      expect(response.body).to include(%(name="kind" value="new_source"))
      expect(response.body).to include(%(name="kind" value="correction"))
      expect(response.body).to include("Scarlet Begonias")
      expect(response.headers["Cache-Control"]).to eq("private, no-store")

      get "/taper/suggest"
      expect(response.body).to include(%(name="kind" value="new_show"))
    end

    it "accepts a browser form post, parses the setlist, and confirms" do
      sign_in(member)
      post "/taper/suggest",
           params: {
             authenticity_token: "ignored-in-test",
             kind: "new_show",
             payload: {
               date: "1972-08-27",
               venue: "Old Renaissance Faire Grounds",
               city: "Veneta",
               source: {
                 url: "https://archive.org/details/gd72",
               },
             },
             setlist_text: "Playing in the Band\nScarlet Begonias >\nFire on the Mountain\n\n",
             note: "the sunshine daydream show",
           }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("review queue")
      suggestion = DiscourseTaper::Suggestion.last
      expect(suggestion).to have_attributes(
        kind: "new_show",
        submitted_by: member,
        note: "the sunshine daydream show",
      )
      expect(suggestion.payload["setlist"]).to eq(
        [
          { "title" => "Playing in the Band" },
          { "title" => "Scarlet Begonias", "notes" => ">" },
          { "title" => "Fire on the Mountain" },
        ],
      )
      expect(suggestion.payload.dig("source", "url")).to eq("https://archive.org/details/gd72")
    end

    it "turns a correction form's setlist into changes" do
      sign_in(member)
      post "/taper/suggest",
           params: {
             kind: "correction",
             date: "1977-05-08",
             payload: {
               changes: {
                 venue: "Barton Hall",
               },
             },
             setlist_text: "Minglewood\nLoser",
           }
      expect(response.status).to eq(200)
      changes = DiscourseTaper::Suggestion.last.payload["changes"]
      expect(changes["venue"]).to eq("Barton Hall")
      expect(changes["setlist"].map { |s| s["title"] }).to eq(%w[Minglewood Loser])
    end
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
