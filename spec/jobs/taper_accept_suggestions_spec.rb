# frozen_string_literal: true

describe Jobs::TaperAcceptSuggestions do
  fab!(:category)
  fab!(:reviewer, :admin)
  fab!(:member, :user)
  fab!(:band, :taper_band)

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
  end

  def propose(date, venue: "Barton Hall", status: "pending")
    DiscourseTaper::Suggestion.create!(
      kind: "new_show",
      band: band,
      origin: "setlist_fm",
      status: status,
      payload: {
        "date" => date,
        "venue" => venue,
        "setlist" => [{ "title" => "Angor" }],
      },
    )
  end

  it "accepts each pending suggestion, skips the rest, and reports to the reviewer" do
    a = propose("2026-09-16", venue: "Underground Arts")
    b = propose("2026-09-10", venue: "Le Poisson Rouge")
    already = propose("2026-09-09", status: "rejected")
    broken = propose("2026-09-04")
    broken.update_columns(payload: broken.payload.merge("venue" => ""))

    messages =
      MessageBus.track_publish("/taper/review/#{reviewer.id}") do
        described_class.new.execute(
          suggestion_ids: [a.id, b.id, already.id, broken.id],
          origin: "setlist_fm",
          reviewer_id: reviewer.id,
        )
      end

    expect(DiscourseTaper::Show.count).to eq(2)
    expect(a.reload).to have_attributes(status: "accepted", reviewed_by: reviewer)
    expect(a.show.setlist_titles).to eq(["Angor"])
    expect(broken.reload.status).to eq("pending")
    expect(messages.size).to eq(1)
    expect(messages.first.data).to include(accepted: 2, failed: 1, origin: "setlist_fm")
    expect(messages.first.user_ids).to eq([reviewer.id])
  end

  it "does nothing for a non-reviewer" do
    a = propose("2026-09-16")
    described_class.new.execute(
      suggestion_ids: [a.id],
      origin: "setlist_fm",
      reviewer_id: member.id,
    )
    expect(a.reload.status).to eq("pending")
  end
end
