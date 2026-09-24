# frozen_string_literal: true

module Jobs
  # Accepts a batch of suggestions on a reviewer's behalf. A trusted show
  # source such as setlist.fm arrives as a few hundred suggestions at
  # once, and each acceptance creates a topic, so this runs off the
  # request and tells the reviewer when it is done.
  class TaperAcceptSuggestions < ::Jobs::Base
    sidekiq_options retry: false

    def execute(args)
      reviewer = User.find_by(id: args[:reviewer_id])
      return if reviewer.nil? || !DiscourseTaper.reviewer?(reviewer)

      ids = Array(args[:suggestion_ids]).map(&:to_i)
      accepted = 0
      failed = 0
      DiscourseTaper::Suggestion
        .pending
        .where(id: ids)
        .order(:id)
        .find_each do |suggestion|
          DiscourseTaper::SuggestionReviewer.new(reviewer: reviewer).accept!(suggestion)
          accepted += 1
        rescue DiscourseTaper::Error, ActiveRecord::RecordInvalid => e
          failed += 1
          Rails.logger.warn(
            "#{DiscourseTaper::PLUGIN_NAME}: bulk accept skipped suggestion #{suggestion.id}: #{e.message}",
          )
        end

      MessageBus.publish(
        "/taper/review/#{reviewer.id}",
        { type: "bulk_accept", origin: args[:origin], accepted: accepted, failed: failed },
        user_ids: [reviewer.id],
      )
    end
  end
end
