require "rails"
require "active_record"
require "minitest/autorun"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :counters, force: true do |t|
    t.integer :value, null: false, default: 0
  end
end

class Counter < ActiveRecord::Base
end

class CounterTest < Minitest::Test
  def test_it_starts_at_zero
    assert_equal 0, Counter.create!.value
  end
end