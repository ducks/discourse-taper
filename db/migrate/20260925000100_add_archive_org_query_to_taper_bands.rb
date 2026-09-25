# frozen_string_literal: true

class AddArchiveOrgQueryToTaperBands < ActiveRecord::Migration[8.0]
  def change
    add_column :taper_bands, :archive_org_query, :string
  end
end
