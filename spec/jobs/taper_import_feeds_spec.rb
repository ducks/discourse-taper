# frozen_string_literal: true

describe Jobs::TaperImportFeeds do
  fab!(:band, :taper_band)

  before do
    SiteSetting.taper_enabled = true
    Discourse.redis.del("taper:last_import_at")
  end

  it "enqueues archive.org for each band, and youtube and setlist.fm only when configured" do
    expect_enqueued_with(
      job: :taper_import_feed,
      args: {
        band_id: band.id,
        importer: "archive_org",
      },
    ) { described_class.new.execute({}) }
    expect(Jobs::TaperImportFeed.jobs.map { |j| j["args"].first["importer"] }).to eq(
      ["archive_org"],
    )

    Jobs::TaperImportFeed.jobs.clear
    Discourse.redis.del("taper:last_import_at")
    SiteSetting.taper_youtube_api_key = "key"
    described_class.new.execute({})
    expect(Jobs::TaperImportFeed.jobs.map { |j| j["args"].first["importer"] }).to contain_exactly(
      "archive_org",
      "youtube",
    )

    Jobs::TaperImportFeed.jobs.clear
    Discourse.redis.del("taper:last_import_at")
    SiteSetting.taper_setlistfm_api_key = "key"
    described_class.new.execute({})
    expect(Jobs::TaperImportFeed.jobs.map { |j| j["args"].first["importer"] }).to contain_exactly(
      "setlist_fm",
      "archive_org",
      "youtube",
    )
  end

  it "respects the interval" do
    described_class.new.execute({})
    Jobs::TaperImportFeed.jobs.clear
    described_class.new.execute({})
    expect(Jobs::TaperImportFeed.jobs).to be_empty
  end
end
