# frozen_string_literal: true

class AddAutoAcceptRecordingsToTaperBands < ActiveRecord::Migration[8.0]
  def change
    add_column :taper_bands, :auto_accept_recordings, :boolean, null: false, default: false
  end
end
