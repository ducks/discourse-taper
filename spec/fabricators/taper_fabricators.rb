# frozen_string_literal: true

Fabricator(:taper_band, class_name: "DiscourseTaper::Band") do
  name { sequence(:taper_band_name) { |i| "Band #{i}" } }
  archive_org_collection { "TestCollection" }
end

Fabricator(:taper_show, class_name: "DiscourseTaper::Show") do
  band { Fabricate(:taper_band) }
  topic { Fabricate(:topic) }
  date { Date.new(1977, 5, 8) }
  venue { "Barton Hall" }
  city { "Ithaca" }
  region { "NY" }
end

Fabricator(:taper_source, class_name: "DiscourseTaper::Source") do
  show { Fabricate(:taper_show) }
  provider { "link" }
  url { "https://example.com/recording" }
end
