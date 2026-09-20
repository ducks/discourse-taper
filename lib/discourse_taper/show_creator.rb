# frozen_string_literal: true

module DiscourseTaper
  # Creates a show and its topic together. The topic's first post is a
  # short, regenerable summary; the card at the top of the topic renders
  # the live record, so the post never has to be kept in sync by hand.
  class ShowCreator
    def initialize(user:)
      @user = user
    end

    def create!(
      band:,
      date:,
      venue:,
      city: nil,
      region: nil,
      country: nil,
      tour: nil,
      setlist: [],
      notes: nil
    )
      category = DiscourseTaper.category
      raise Error.new("category_not_configured") if category.nil?

      sequence = Show.where(band_id: band.id, date: date).maximum(:sequence).to_i + 1
      show =
        Show.new(
          band: band,
          date: date,
          sequence: sequence,
          venue: venue,
          city: city,
          region: region,
          country: country,
          tour: tour,
          setlist: setlist,
          notes: notes,
          created_by: @user,
        )

      Show.transaction do
        post =
          PostCreator.create!(
            @user,
            title: show.title,
            category: category.id,
            raw: intro_for(show),
            skip_validations: true,
          )
        show.topic_id = post.topic_id
        show.save!
      end

      show
    end

    private

    def intro_for(show)
      lines = [
        I18n.t(
          "taper.topic_intro",
          band: show.band.name,
          location: show.location,
          date: show.date.iso8601,
        ),
      ]
      if show.setlist.any?
        lines << ""
        lines << "**#{I18n.t("taper.setlist")}**"
        show.setlist.each_with_index { |song, i| lines << "#{i + 1}. #{song["title"]}" }
      end
      lines.join("\n")
    end
  end
end
