# frozen_string_literal: true

describe DiscourseTaper::SuggestionReviewer do
  fab!(:category)
  fab!(:reviewer, :admin)
  fab!(:member, :user)
  fab!(:band, :taper_band)

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
  end

  let(:reviewer_service) { described_class.new(reviewer: reviewer) }

  it "accepts a new_show suggestion into a topic plus record, with its source" do
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "archive_org",
        payload: {
          "date" => "1977-05-08",
          "venue" => "Barton Hall",
          "city" => "Ithaca",
          "external_id" => "gd1977-05-08.sbd",
          "setlist" => [{ "title" => "New Minglewood Blues" }, { "title" => "Loser" }],
          "source" => {
            "provider" => "archive_org",
            "external_id" => "gd1977-05-08.sbd",
            "url" => "https://archive.org/details/gd1977-05-08.sbd",
            "kind" => "soundboard",
            "format" => "flac",
            "taper_name" => "Betty Cantor",
          },
        },
      )

    show = reviewer_service.accept!(suggestion, note: "looks right")

    expect(show).to be_persisted
    expect(show.topic.category).to eq(category)
    expect(show.topic.title).to include("Barton Hall")
    expect(show.topic.first_post.raw).to include("New Minglewood Blues")
    expect(show.setlist_titles).to eq(["New Minglewood Blues", "Loser"])
    expect(show.sources.count).to eq(1)
    expect(show.sources.first).to have_attributes(
      kind: "soundboard",
      format: "flac",
      taper_name: "Betty Cantor",
    )
    expect(suggestion.reload).to have_attributes(
      status: "accepted",
      reviewed_by: reviewer,
      review_note: "looks right",
    )
  end

  it "attaches a new_source to the matched show, and refuses when no show exists" do
    show = Fabricate(:taper_show, band: band, topic: Fabricate(:topic, category: category))
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_source",
        band: band,
        origin: "user",
        submitted_by: member,
        payload: {
          "date" => "1977-05-08",
          "url" => "https://youtube.com/watch?v=abc",
          "provider" => "youtube",
          "kind" => "video",
        },
      )

    source = reviewer_service.accept!(suggestion)
    expect(source.show).to eq(show)
    expect(source.submitted_by).to eq(member)
    expect(source.kind).to eq("video")

    orphan =
      DiscourseTaper::Suggestion.create!(
        kind: "new_source",
        band: band,
        origin: "user",
        payload: {
          "date" => "1999-01-01",
          "url" => "https://example.com/x",
        },
      )
    expect { reviewer_service.accept!(orphan) }.to raise_error(DiscourseTaper::Error) { |e|
      expect(e.key).to eq("show_not_found")
    }
    expect(orphan.reload).to be_pending
  end

  it "applies only allowed correction fields" do
    show = Fabricate(:taper_show, band: band, venue: "Barton Hal")
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "correction",
        band: band,
        show: show,
        origin: "user",
        payload: {
          "changes" => {
            "venue" => "Barton Hall",
            "tour" => "Spring 1977",
            "topic_id" => 999,
            "band_id" => 999,
          },
        },
      )

    reviewer_service.accept!(suggestion)
    show.reload
    expect(show.venue).to eq("Barton Hall")
    expect(show.tour).to eq("Spring 1977")
    expect(show.band).to eq(band)
  end

  it "rejects, and refuses to review twice" do
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "user",
        payload: {
          "date" => "1977-05-08",
          "venue" => "X",
        },
      )
    reviewer_service.reject!(suggestion, note: "duplicate")
    expect(suggestion.reload).to have_attributes(status: "rejected", review_note: "duplicate")
    expect { reviewer_service.accept!(suggestion) }.to raise_error(DiscourseTaper::Error)
  end
end
