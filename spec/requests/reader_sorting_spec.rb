# frozen_string_literal: true

RSpec.describe "Taper reader sorting" do
  fab!(:category)
  fab!(:band, :taper_band)
  fab!(:early) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2025, 2, 1),
      topic: Fabricate(:topic, category: category),
      setlist: [{ "title" => "Shared" }, { "title" => "Alpha" }],
    )
  end
  fab!(:late) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2025, 10, 1),
      topic: Fabricate(:topic, category: category),
      setlist: [{ "title" => "Shared" }, { "title" => "Zebra" }],
    )
  end
  fab!(:encore) do
    Fabricate(
      :taper_show,
      band: band,
      date: late.date,
      sequence: 2,
      topic: Fabricate(:topic, category: category),
      setlist: [{ "title" => "Shared" }],
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
  end

  def html
    Nokogiri.HTML5(response.body)
  end

  it "sorts performance history in either direction without changing first/last facts" do
    get "/taper/songs/shared.json"
    expect(response.parsed_body.dig("song", "nights").map { |n| n["url"] }).to eq(
      [encore.url, late.url, early.url],
    )
    get "/taper/songs/shared.json?sort=oldest"
    expect(response.parsed_body.dig("song", "nights").map { |n| n["url"] }).to eq(
      [early.url, late.url, encore.url],
    )
    %w[newest oldest].each do |sort|
      get "/taper/songs/shared?sort=#{sort}"
      expect(html.css(".taper-facts a").map { |a| a["href"] }).to eq([early.url, encore.url])
      expect(html.at_css('link[rel="canonical"]')["href"]).to eq(
        "http://test.localhost/taper/songs/shared",
      )
      expect(html.at_css('link[type="application/json"]')["href"]).to eq(
        "/taper/songs/shared.json?sort=#{sort}",
      )
    end
  end

  it "sorts shows and preserves filters and language" do
    get "/taper.json?sort=oldest"
    expect(response.parsed_body["shows"].map { |s| s["id"] }).to eq([early.id, late.id, encore.id])
    get "/taper?year=2025&venue=Barton%20Hall&sort=oldest&lang=fr"
    expect(response.status).to eq(200)
    expect(html.css(".taper-show-row__venue").map { |a| a["href"] }).to eq(
      [early.url, late.url, encore.url],
    )
    form = html.at_css("form.taper-sort")
    expect(form.at_css('input[name="year"]')["value"]).to eq("2025")
    expect(form.at_css('input[name="venue"]')["value"]).to eq("Barton Hall")
    expect(form.at_css('input[name="lang"]')["value"]).to eq("fr")
    expect(html.at_css('.taper-top__lang a[hreflang="en"]')["href"]).to include("sort=oldest")
    expect(html.css("head link[hreflang]").map { |n| n["href"] }.join).not_to include("sort=")
  end

  it "sorts the song index by count, title or latest performance" do
    {
      "most_played" => %w[Shared Alpha Zebra],
      "least_played" => %w[Alpha Zebra Shared],
      "title" => %w[Alpha Shared Zebra],
      "recently_played" => %w[Shared Zebra Alpha],
    }.each do |sort, titles|
      get "/taper/songs.json?sort=#{sort}"
      expect(response.parsed_body["songs"].map { |s| s["title"] }).to eq(titles)
    end
  end

  it "sorts media by publication date or title with undated items last" do
    [
      ["Zulu", Date.new(2024, 1, 1)],
      ["Beta", Date.new(2025, 1, 1)],
      ["Alpha", nil],
    ].each_with_index do |(title, date), n|
      DiscourseTaper::MediaItem.create!(
        band: band,
        title: title,
        published_on: date,
        provider: "youtube",
        external_id: "video#{n}",
        url: "https://example.com/#{n}",
        kind: "video",
      )
    end
    {
      "newest" => %w[Beta Zulu Alpha],
      "oldest" => %w[Zulu Beta Alpha],
      "title" => %w[Alpha Beta Zulu],
    }.each do |sort, titles|
      get "/taper/media.json?sort=#{sort}"
      expect(response.parsed_body["media"].map { |m| m["title"] }).to eq(titles)
      get "/taper/media?sort=#{sort}"
      expect(html.css(".taper-media__item .taper-show-row__venue").map(&:text)).to eq(titles)
    end
  end

  it "sorts recordings by date added or title in HTML and JSON" do
    first = Fabricate(:taper_source, show: early, title: "Zulu", created_at: 2.days.ago)
    second = Fabricate(:taper_source, show: early, title: "Alpha", created_at: 1.day.ago)
    {
      "added_oldest" => [first, second],
      "added_newest" => [second, first],
      "title" => [second, first],
    }.each do |sort, sources|
      get "#{early.url}.json?sort=#{sort}"
      expect(response.parsed_body.dig("show", "sources").map { |s| s["id"] }).to eq(
        sources.map(&:id),
      )
      get "#{early.url}?sort=#{sort}"
      expect(html.css(".taper-source__title").map(&:text)).to eq(sources.map(&:title))
    end
  end

  it "falls back safely for unknown sort values and supports secondary bands" do
    other = Fabricate(:taper_band)
    show =
      Fabricate(
        :taper_show,
        band: other,
        topic: Fabricate(:topic, category: category),
        setlist: [{ "title" => "Shared" }],
      )
    get "/taper/#{other.slug}/songs/shared?sort=oldest"
    expect(html.at_css("form.taper-sort")["action"]).to eq("/taper/#{other.slug}/songs/shared")
    get "/taper/songs/shared.json", params: { sort: "date; DROP TABLE taper_shows" }
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("song", "nights").map { |n| n["url"] }).to eq(
      [encore.url, late.url, early.url],
    )
    expect(DiscourseTaper::Show.exists?(show.id)).to eq(true)
  end
end
