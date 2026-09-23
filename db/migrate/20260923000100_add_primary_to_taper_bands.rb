# frozen_string_literal: true

class AddPrimaryToTaperBands < ActiveRecord::Migration[8.0]
  def up
    add_column :taper_bands, :primary, :boolean, null: false, default: false
    # At most one primary band per site.
    add_index :taper_bands, :primary, unique: true, where: "\"primary\""
    # An existing single-band site keeps behaving as it did: that band is
    # the primary and drops out of URLs and titles.
    execute <<~SQL
      UPDATE taper_bands SET "primary" = true
      WHERE id = (SELECT id FROM taper_bands ORDER BY id LIMIT 1)
        AND (SELECT COUNT(*) FROM taper_bands) = 1
    SQL
  end

  def down
    remove_index :taper_bands, :primary
    remove_column :taper_bands, :primary
  end
end
