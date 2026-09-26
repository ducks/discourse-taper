# frozen_string_literal: true

describe "Taper review queue" do
  fab!(:category) { Fabricate(:category, name: "Shows") }
  fab!(:reviewers, :group)
  fab!(:reviewer, :user)
  fab!(:band) { Fabricate(:taper_band, name: "Furthur", archive_org_collection: "Furthur") }

  # The shape the archive.org importer files after grouping a night's
  # recordings: one suggestion, every source, the majority venue and the
  # other spellings it saw.
  fab!(:grouped) do
    DiscourseTaper::Suggestion.create!(
      kind: "new_show",
      band: band,
      origin: "archive_org",
      payload: {
        "date" => "2011-07-16",
        "venue" => "Bethel Woods Center for the Arts",
        "venue_spellings" => {
          "Bethel Woods Center for the Arts" => 14,
          "Bethel Woods" => 3,
        },
        "city" => "Bethel",
        "region" => "NY",
        "external_id" => "furthur2011-07-16.sbd",
        "sources" => [
          {
            "provider" => "archive_org",
            "external_id" => "furthur2011-07-16.sbd",
            "url" => "https://archive.org/details/a",
            "title" => "Soundboard",
            "kind" => "soundboard",
            "format" => "flac",
            "duration_seconds" => 9000,
          },
          {
            "provider" => "archive_org",
            "external_id" => "furthur2011-07-16.aud1",
            "url" => "https://archive.org/details/b",
            "title" => "Schoeps AUD",
            "kind" => "audience",
            "format" => "flac",
            "taper_name" => "Jim",
          },
          {
            "provider" => "archive_org",
            "external_id" => "furthur2011-07-16.aud2",
            "url" => "https://archive.org/details/c",
            "title" => "DPA AUD",
            "kind" => "audience",
            "format" => "flac",
          },
        ],
      },
    )
  end

  fab!(:existing) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2010, 11, 21),
      venue: "MSG",
      topic: Fabricate(:topic, category: category),
    )
  end
  fab!(:correction) do
    DiscourseTaper::Suggestion.create!(
      kind: "correction",
      band: band,
      show: existing,
      origin: "user",
      submitted_by: Fabricate(:user),
      note: "official name",
      payload: {
        "changes" => {
          "venue" => "Madison Square Garden",
        },
      },
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_reviewer_groups = reviewers.id.to_s
    reviewers.add(reviewer)
    sign_in(reviewer)
  end

  it "shows grouped suggestions and accepts a show with every recording" do
    visit("/taper/review")

    expect(page).to have_css(".taper-suggestion", count: 2)
    row = find(".taper-suggestion--new_show")
    expect(row).to have_content("2011-07-16 · Bethel Woods Center for the Arts")
    expect(row).to have_content("Bethel Woods (3)")
    expect(row).to have_content("found by archive.org")

    row.find(".taper-suggestion__toggle").click
    expect(row).to have_css(".taper-suggestion__recordings li", count: 3)
    expect(row).to have_content("Schoeps AUD")

    expect(row).to have_css(".taper-suggestion__venue-input")
    row.find(".taper-suggestion__venue-input").fill_in(
      with: "Bethel Woods Center for the Arts, Bethel NY",
    )
    row.find(".taper-suggestion__review-note").fill_in(with: "looks right")
    row.find(".taper-suggestion__accept").click

    expect(page).to have_css(".taper-suggestion", count: 1)
    expect(page).to have_css(".taper-review__decisions", text: "Accepted 2011-07-16")
    expect(page).to have_link("View show", href: "/taper/2011-07-16")

    show = DiscourseTaper::Show.find_by(band: band, date: Date.new(2011, 7, 16))
    expect(show).to be_present
    expect(show.venue).to eq("Bethel Woods Center for the Arts, Bethel NY")
    expect(show.venue_record.aliases).to include("bethel woods")
    expect(show.sources.count).to eq(3)
    expect(grouped.reload).to have_attributes(
      status: "accepted",
      reviewed_by: reviewer,
      review_note: "looks right",
    )
  end

  it "accepts every pending show from an importer at once" do
    Jobs.run_immediately!
    visit("/taper/review")

    find(".taper-review__accept-all", text: "Accept all 1 from archive.org").click
    find(".dialog-footer .btn-primary").click

    expect(page).to have_css(".taper-review__decisions", text: "Accepting 1 shows from archive.org")
    # The job runs deferred after the response and reports back over
    # MessageBus on the reviewer's channel; polling is the fallback.
    expect(page).to have_css(
      ".taper-review__decisions",
      text: "Accepted 1 shows from archive.org",
      wait: 30,
    )
    expect(page).to have_css(".taper-suggestion", count: 1)
    expect(page).to have_no_css(".taper-review__accept-all")
    show = DiscourseTaper::Show.find_by(band: band, date: Date.new(2011, 7, 16))
    expect(show).to be_present
    expect(show.sources.count).to eq(3)
    expect(grouped.reload).to have_attributes(status: "accepted", reviewed_by: reviewer)
  end

  it "shows a correction's changes and rejects it" do
    visit("/taper/review")

    row = find(".taper-suggestion--correction")
    expect(row).to have_content("2010-11-21")
    expect(row).to have_content("Madison Square Garden")
    expect(row).to have_content("official name")

    row.find(".taper-suggestion__reject").click

    expect(page).to have_css(".taper-review__decisions", text: "Rejected 2010-11-21")
    expect(correction.reload).to have_attributes(status: "rejected", reviewed_by: reviewer)
    expect(existing.reload.venue).to eq("MSG")
  end

  it "shows a claim with the recording it is about and accepts it" do
    source =
      Fabricate(
        :taper_source,
        show: existing,
        provider: "youtube",
        title: "Full set at MSG",
        taper_name: "DirtyMovies76",
      )
    claimant = Fabricate(:user, username: "dirtymovies")
    DiscourseTaper::Suggestion.create!(
      kind: "claim",
      band: band,
      show: existing,
      origin: "user",
      submitted_by: claimant,
      note: "It is my channel.",
      payload: {
        "source_id" => source.id,
      },
    )

    visit("/taper/review")

    row = find(".taper-suggestion--claim")
    expect(row).to have_content("2010-11-21")
    expect(row).to have_content("@dirtymovies says this recording is theirs")
    expect(row).to have_link("Full set at MSG")
    expect(row).to have_content("currently credited to DirtyMovies76")
    expect(row).to have_content("It is my channel.")

    row.find(".taper-suggestion__accept").click

    expect(page).to have_css(".taper-review__decisions", text: "Accepted 2010-11-21")
    expect(source.reload.taper).to eq(claimant)
  end

  it "offers the queue in the sidebar to reviewers only" do
    visit("/")
    expect(page).to have_css(".sidebar-section-link[data-link-name='taper-review']", visible: :all)

    sign_in(Fabricate(:user))
    visit("/")
    expect(page).to have_no_css(
      ".sidebar-section-link[data-link-name='taper-review']",
      visible: :all,
    )
  end
end
