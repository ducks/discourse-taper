# frozen_string_literal: true

# Every id column that references users, topics, uploads, or the plugin's
# own tables was created as a 4-byte integer. Core's ids are bigint, and
# its test suite sets every sequence past the 32-bit range precisely to
# catch this: inserting a real user or topic id raised
# ActiveModel::RangeError in CI. Widen them all.
class ChangeTaperForeignKeysToBigint < ActiveRecord::Migration[8.0]
  COLUMNS = {
    taper_shows: %i[band_id topic_id created_by_id],
    taper_sources: %i[show_id upload_id taper_id submitted_by_id],
    taper_suggestions: %i[band_id show_id submitted_by_id reviewed_by_id],
  }.freeze

  def up
    COLUMNS.each { |table, columns| columns.each { |column| change_column table, column, :bigint } }
  end

  def down
    COLUMNS.each do |table, columns|
      columns.each { |column| change_column table, column, :integer }
    end
  end
end
