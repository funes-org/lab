require_relative "../support/boot"

ActiveRecord::Schema.define do
  create_table "product_prices", id: false, force: :cascade do |t|
    t.string "sku", null: false
    t.decimal "price", precision: 12, scale: 2, null: false
    t.date "from_date", null: false
    t.date "to_date"
    t.integer "version", null: false
    t.index [ "sku", "version" ], unique: true
  end
end

# app/models/product_price_table.rb
class ProductPriceTable < ActiveRecord::Base
  self.table_name = "product_prices"
  self.implicit_order_column = "version"

  validates :price, presence: true, numericality: { greater_than: 0 }

  scope :for, ->(sku) { where(sku:) }
  scope :at, ->(date) { where(from_date: ..date).where("to_date IS NULL OR to_date > ?", date) }
end

module SkuHistoricEvents
  # app/models/sku_historic_events/price_set.rb
  class PriceSet < Funes::Event
    attribute :price, :decimal
    attribute :from, :date
    attribute :to, :date
  end
end

# app/models/price_history.rb
class PriceHistory
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :idx
  alias :sku :idx

  def entries
    @entries ||= []
  end

  def sync_prices!
    ProductPriceTable.upsert_all(@entries.map { |entry| entry.merge(sku:) },
                                 unique_by: %i[sku version])
  end
end

# app/projections/historic_price_projection.rb
class HistoricPriceProjection < Funes::Projection
  materialization_model PriceHistory
  persist_materialization_model_with :sync_prices!

  interpretation_for SkuHistoricEvents::PriceSet do |state, pricing_event, _at|
    state.entries << { price: pricing_event.price,
                       from_date: pricing_event.from,
                       to_date: pricing_event.to,
                       version: pricing_event.version }
    state
  end
end

class SkuHistoryEventStream < Funes::EventStream
  add_transactional_projection HistoricPriceProjection
end

# [tests] test/event_streams/sku_history_event_stream_test.rb
class SkuHistoryEventStreamTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  jan1 = Date.new(2026, 1, 1)
  feb1 = Date.new(2026, 2, 1)
  mar1 = Date.new(2026, 3, 1)
  apr1 = Date.new(2026, 4, 1)
  may1 = Date.new(2026, 5, 1)

  describe "priced periods with a gap (the README chart)" do
    let(:sku) { "CHART-#{name}" }

    before do
      stream = SkuHistoryEventStream.for(sku)
      stream.append(SkuHistoricEvents::PriceSet.new(price: 1, from: jan1, to: feb1))
      stream.append(SkuHistoricEvents::PriceSet.new(price: 3, from: feb1, to: mar1))
      stream.append(SkuHistoricEvents::PriceSet.new(price: 2, from: apr1, to: may1))
    end

    test "materializes one row per priced period" do
      periods = ProductPriceTable.for(sku).order(:version).to_a
      assert_equal 3, periods.size

      january_period, february_period, april_period = periods

      assert_equal 1, january_period.price
      assert_equal jan1, january_period.from_date
      assert_equal feb1, january_period.to_date

      assert_equal 3, february_period.price
      assert_equal feb1, february_period.from_date
      assert_equal mar1, february_period.to_date

      assert_equal 2, april_period.price
      assert_equal apr1, april_period.from_date
      assert_equal may1, april_period.to_date
    end

    test "answers the price of the sku at any given date" do
      assert_equal 1, ProductPriceTable.for(sku).at(Date.new(2026, 1, 15)).sole.price
      assert_equal 3, ProductPriceTable.for(sku).at(Date.new(2026, 2, 15)).sole.price
      assert_equal 2, ProductPriceTable.for(sku).at(Date.new(2026, 4, 15)).sole.price

      assert_equal 3, ProductPriceTable.for(sku).at(feb1).sole.price

      assert_empty ProductPriceTable.for(sku).at(Date.new(2026, 3, 15))
    end
  end
end
