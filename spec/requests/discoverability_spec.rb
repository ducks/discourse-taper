# frozen_string_literal: true

RSpec.describe "Taper discoverability" do
  fab!(:category)
  fab!(:band) { Fabricate(:taper_band, name: "Example Band") }
  fab!(:show) { Fabricate(:taper_show, band: band, topic: Fabricate(:topic, category: category)) }
  fab!(:source) do
    Fabricate(
      :taper_source,
      show: show,
      kind: "video",
      provider: "youtube",
      external_id: "abcdefghijk",
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.enable_sitemap = true
    SiteSetting.allow_index_in_robots_txt = true
    SiteSetting.default_locale = "en"
  end

  def html
    Nokogiri.HTML5(response.body)
  end

  def locations
    Nokogiri.XML(response.body).remove_namespaces!.xpath("//loc").map(&:text)
  end

  it "advertises a separate sitemap without replacing Discourse's sitemap" do
    get "/robots.txt"
    expect(response.body).to include(
      "Sitemap: http://test.localhost/taper/sitemap.xml",
      "Sitemap: http://test.localhost/sitemap.xml",
    )
    get "/taper/sitemap.xml"
    expect(response.status).to eq(200)
    expect(locations).to include(
      "http://test.localhost/taper/sitemaps/shows/1.xml",
      "http://test.localhost/taper/sitemaps/recordings/1.xml",
    )
    get "/taper/sitemaps/shows/1.xml"
    expect(locations).to include("http://test.localhost#{show.url}")
    get "/taper/sitemaps/recordings/1.xml"
    expect(locations).to include("http://test.localhost/taper/recordings/#{source.id}")
  end

  it "excludes hidden, private, deleted and personal-message topics even for staff" do
    hidden =
      Fabricate(
        :taper_show,
        band: band,
        sequence: 2,
        topic: Fabricate(:topic, category: category, visible: false),
      )
    private_show =
      Fabricate(
        :taper_show,
        band: band,
        sequence: 3,
        topic: Fabricate(:topic, category: Fabricate(:private_category, group: Fabricate(:group))),
      )
    deleted =
      Fabricate(:taper_show, band: band, sequence: 4, topic: Fabricate(:topic, category: category))
    deleted.topic.trash!
    pm = Fabricate(:taper_show, band: band, sequence: 5, topic: Fabricate(:private_message_topic))
    [hidden, private_show, deleted, pm].each { |s| Fabricate(:taper_source, show: s) }
    sign_in(Fabricate(:admin))
    get "/taper/sitemaps/shows/1.xml"
    expect(locations).to eq(["http://test.localhost#{show.url}"])
    get "/taper/sitemaps/recordings/1.xml"
    expect(locations).to eq(["http://test.localhost/taper/recordings/#{source.id}"])
  end

  it "does not expose a private archive or a disabled plugin" do
    SiteSetting.taper_category_id = Fabricate(:private_category, group: Fabricate(:group)).id
    get "/taper/sitemap.xml"
    expect(response.status).to eq(404)
    get "/robots.txt"
    expect(response.body).not_to include("/taper/sitemap.xml")
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_enabled = false
    get "/taper/sitemap.xml"
    expect(response.status).to eq(404)
  end

  it "omits the sitemap on login-required and no-index sites" do
    SiteSetting.login_required = true
    get "/robots.txt"
    expect(response.body).not_to include("/taper/sitemap.xml")
    SiteSetting.login_required = false
    SiteSetting.allow_index_in_robots_txt = false
    get "/taper/sitemap.xml"
    expect(response.status).to eq(404)
  end

  it "paginates sitemap entries and preserves sequence and secondary-band URLs" do
    stub_const(DiscourseTaper::SitemapsController, "PAGE_SIZE", 1) do
      second =
        Fabricate(
          :taper_show,
          band: band,
          sequence: 2,
          topic: Fabricate(:topic, category: category),
        )
      other = Fabricate(:taper_show, topic: Fabricate(:topic, category: category))
      get "/taper/sitemaps/shows/2.xml"
      expect(locations).to eq(["http://test.localhost#{second.url}"])
      get "/taper/sitemaps/shows/3.xml"
      expect(locations).to eq(["http://test.localhost#{other.url}"])
      get "/taper/sitemaps/shows/4.xml"
      expect(response.status).to eq(404)
    end
  end

  it "includes songs and indexes, and removes deleted recordings" do
    show.update!(setlist: [{ "title" => "One Song" }])
    get "/taper/sitemaps/songs-#{band.id}/1.xml"
    expect(locations).to include("http://test.localhost/taper/songs/one-song")
    get "/taper/sitemaps/bands/1.xml"
    expect(locations).to include(
      "http://test.localhost/taper",
      "http://test.localhost/taper/media",
      "http://test.localhost/taper/songs",
    )
    source.destroy!
    get "/taper/sitemaps/recordings/1.xml"
    expect(response.status).to eq(404)
  end

  it "normalizes tracking parameters while keeping meaningful filters" do
    get "/taper?utm_source=share&year=1977&foo=bar"
    expect(html.at_css('link[rel="canonical"]')["href"]).to eq(
      "http://test.localhost/taper?year=1977",
    )
    expect(html.at_css('meta[name="description"]')["content"]).to include("Example Band", "1977")
    expect(html.css("link[hreflang]").map { |n| n["href"] }).to contain_exactly(
      "http://test.localhost/taper?year=1977",
      "http://test.localhost/taper?lang=fr&year=1977",
    )
  end

  it "uses consistent localized canonicals and reciprocal alternates" do
    get "#{show.url}?lang=fr&utm_source=share"
    expect(html.at_css("html")["lang"]).to eq("fr")
    expect(html.at_css('link[rel="canonical"]')["href"]).to eq(
      "http://test.localhost#{show.url}?lang=fr",
    )
    expect(html.css("link[hreflang]").map { |n| n["href"] }).to contain_exactly(
      "http://test.localhost#{show.url}",
      "http://test.localhost#{show.url}?lang=fr",
    )
    get show.url
    expect(html.at_css('link[rel="canonical"]')["href"]).to end_with("?lang=fr")
    get "#{show.url}?lang=en"
    expect(html.at_css('link[rel="canonical"]')["href"]).to eq("http://test.localhost#{show.url}")
  end

  it "noindexes empty filters and rejects invalid years" do
    get "/taper?year=1900"
    expect(response.status).to eq(200)
    expect(html.at_css('meta[name="robots"]')["content"]).to eq("noindex,follow")
    get "/taper?year=garbage"
    expect(response.status).to eq(404)
  end

  it "emits descriptions, social tags and safe structured data for reader pages" do
    source.update!(title: '</script><script>alert("bad")</script>')
    [
      "/taper",
      show.url,
      "/taper/media",
      "/taper/songs",
      "/taper/recordings/#{source.id}",
    ].each do |url|
      get url
      expect(response.status).to eq(200)
      expect(html.at_css('meta[name="description"]')["content"]).to be_present
      expect(html.at_css('meta[property="og:title"]')["content"]).to be_present
      expect(html.at_css('meta[property="og:url"]')["content"]).to eq(
        html.at_css('link[rel="canonical"]')["href"],
      )
      expect(html.at_css('meta[name="twitter:card"]')).to be_present
      graph = JSON.parse(html.at_css('script[type="application/ld+json"]').text)["@graph"]
      expect(graph.map { |n| n["@type"] }).to include("MusicGroup", "BreadcrumbList")
      expect(html.css("script").any? { |n| n.text == 'alert("bad")' }).to eq(false)
    end
    expect(
      graph = JSON.parse(html.at_css('script[type="application/ld+json"]').text)["@graph"],
    ).to include(a_hash_including("@type" => "VideoObject", "name" => source.title))
  end

  it "does not advertise the forum Markdown list as the archive homepage" do
    SiteSetting.has_login_hint = false
    SiteSetting.default_homepage = "taper"
    get "/"
    expect(response.headers["Link"].to_s).not_to include("latest.md")
    graph = JSON.parse(html.at_css('script[type="application/ld+json"]').text)["@graph"]
    expect(graph.map { |n| n["@type"] }).to include("WebSite")
  end
end
