class EnablePgExtensions < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto"
    enable_extension "ltree"
    enable_extension "citext"
  end

  def down
    disable_extension "citext"
    disable_extension "ltree"
    disable_extension "pgcrypto"
  end
end
