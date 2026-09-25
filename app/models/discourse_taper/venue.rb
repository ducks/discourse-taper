# frozen_string_literal: true

module DiscourseTaper
  # A canonical venue plus every spelling known to mean it. Reviewers answer
  # "what is this venue" once; after that the same room resolves itself
  # under any spelling an importer produces.
  class Venue < ActiveRecord::Base
    self.table_name = "taper_venues"

    FUZZY_THRESHOLD = 0.45

    has_many :shows, class_name: "DiscourseTaper::Show", foreign_key: :venue_id, dependent: :nullify

    validates :name, presence: true, length: { maximum: 200 }
    validates :slug, presence: true, uniqueness: true

    before_validation :derive_slug
    after_create { learn!([name]) }

    # Lowercase ASCII words only: curly apostrophes, punctuation, and a
    # leading "the" all disappear, so "Lockn’ Festival" and "lockn festival"
    # become the same key.
    def self.normalize(value)
      value
        .to_s
        .unicode_normalize(:nfkd)
        .gsub(/[^\x00-\x7F]/, "")
        .downcase
        .gsub(/\bthe\b/, "")
        .gsub(/[^a-z0-9]+/, " ")
        .strip
    end

    def self.find_by_alias(spelling)
      key = normalize(spelling)
      return nil if key.blank?
      where("aliases @> ?", [key].to_json).first
    end

    # Best trigram match on the name, with its score, or nil. Similarity
    # alone is not enough: "Mann Center" scores 0.46 against "Saratoga
    # Performing Arts Center" on the shared word, so the first word must
    # also agree. Venues are named by their first word far more reliably
    # than by their last, and a typo there simply falls through to the
    # reviewer, who teaches the alias once.
    def self.fuzzy(spelling, threshold: FUZZY_THRESHOLD)
      key = normalize(spelling)
      return nil if key.blank?
      first_word = key.split.first
      quoted = connection.quote(key)
      candidates =
        select("taper_venues.*, similarity(lower(name), #{quoted}) AS score")
          .where("similarity(lower(name), #{quoted}) >= ?", threshold)
          .order(Arel.sql("score DESC"))
          .limit(5)
      venue = candidates.find { |v| normalize(v.name).split.first == first_word }
      venue && [venue, venue.score.to_f]
    end

    # Resolves an accepted spelling to an existing venue by alias, else
    # creates one. The reviewer-typed name is canonical.
    def self.find_or_create_canonical!(name:, city: nil, region: nil, country: nil)
      find_by_alias(name) || create!(name: name.to_s.strip, city:, region:, country:)
    end

    def learn!(spellings)
      keys = Array(spellings).map { |s| self.class.normalize(s) }.compact_blank
      fresh = (keys + [self.class.normalize(name)]).uniq - aliases
      update!(aliases: aliases + fresh) if fresh.any?
      self
    end

    private

    def derive_slug
      self.slug = name.to_s.parameterize if slug.blank? && name.present?
    end
  end
end

# == Schema Information
#
# Table name: taper_venues
#
#  id         :bigint           not null, primary key
#  aliases    :jsonb            not null
#  city       :string
#  country    :string
#  name       :string           not null
#  region     :string
#  slug       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_taper_venues_on_aliases    (aliases) USING gin
#  index_taper_venues_on_name_trgm  (name gin_trgm_ops) USING gin
#  index_taper_venues_on_slug       (slug) UNIQUE
#
