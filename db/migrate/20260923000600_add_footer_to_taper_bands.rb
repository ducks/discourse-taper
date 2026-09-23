# frozen_string_literal: true

class AddFooterToTaperBands < ActiveRecord::Migration[8.0]
  def change
    add_column :taper_bands, :footer, :text
  end
end
