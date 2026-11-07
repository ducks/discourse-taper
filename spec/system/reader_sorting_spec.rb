# frozen_string_literal: true

describe "Taper reader sorting" do
  fab!(:category)
  fab!(:band, :taper_band)
  fab!(:early) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2024, 1, 1),
      topic: Fabricate(:topic, category: category),
      setlist: [{ "title" => "Shared" }],
    )
  end
  fab!(:late) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2025, 1, 1),
      topic: Fabricate(:topic, category: category),
      setlist: [{ "title" => "Shared" }],
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
  end

  it "switches the song history order with the GET form on desktop and mobile" do
    visit "/taper/songs/shared"
    expect(page).to have_css(".taper-show-row", count: 2)
    expect(all(".taper-show-row__date").map(&:text)).to eq(%w[2025-01-01 2024-01-01])
    select "Oldest first", from: "Sort by"
    click_button "Apply"
    expect(page).to have_current_path(/sort=oldest/)
    expect(all(".taper-show-row__date").map(&:text)).to eq(%w[2024-01-01 2025-01-01])
    page.current_window.resize_to(390, 844)
    select "Newest first", from: "Sort by"
    click_button "Apply"
    expect(page).to have_current_path(/sort=newest/)
    expect(all(".taper-show-row__date").map(&:text)).to eq(%w[2025-01-01 2024-01-01])
    expect(
      page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth + 1"),
    ).to eq(true)
  ensure
    page.current_window.resize_to(1400, 900)
  end
end
