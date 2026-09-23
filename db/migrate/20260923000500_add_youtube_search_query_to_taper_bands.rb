# frozen_string_literal: true

class AddYoutubeSearchQueryToTaperBands < ActiveRecord::Migration[8.0]
  def change
    add_column :taper_bands, :youtube_search_query, :string
  end
end
