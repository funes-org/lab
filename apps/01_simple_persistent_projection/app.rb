require_relative "../support/boot"

ActiveRecord::Schema.define do
  create_table "debts", id: false, force: :cascade do |t|
    t.string "idx", null: false
    t.date "contract_date", null: false
    t.date "last_event_date", null: false
    t.decimal "outstanding_balance", precision: 12, scale: 2, null: false
    t.integer "status", default: 0
    t.index [ "idx" ], name: "index_debts_on_idx", unique: true
  end
end

# app/models/debt.rb
class Debt < ActiveRecord::Base
  self.primary_key = "idx"

  enum :status, { open: 0, repaid: 1 }

  validates :outstanding_balance, presence: true,
            numericality: { greater_than_or_equal_to: 0 }
end

module DebtEvents
  # app/models/debt_events/issued.rb
  class Issued < Funes::Event
    attribute :principal, :decimal
    attribute :at, :date

    validates :principal, presence: true, numericality: { greater_than: 0 }
    validates :at, presence: true
  end

  # app/models/debt_events/payment_received.rb
  class PaymentReceived < Funes::Event
    attribute :principal, :decimal
    attribute :at, :date

    validates :principal, presence: true, numericality: { greater_than: 0 }
    validates :at, presence: true
  end
end

# app/projections/debt_projection.rb
class DebtProjection < Funes::Projection
  materialization_model Debt

  interpretation_for DebtEvents::Issued do |state, issuance_event, issued_at|
    state.assign_attributes(outstanding_balance: issuance_event.principal,
                            status: :open,
                            contract_date: issued_at,
                            last_event_date: issued_at)
    state
  end

  interpretation_for DebtEvents::PaymentReceived do |state, payment_event, paid_at|
    new_outstanding_balance = state.outstanding_balance - payment_event.principal
    state.assign_attributes(outstanding_balance: new_outstanding_balance,
                            status: new_outstanding_balance.zero? ? :repaid : :open,
                            last_event_date: paid_at)
    state
  end
end


# [tests] test/projections/debt_projection_test.rb
class DebtProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include Funes::ProjectionTestHelper

  projection DebtProjection

  describe "debt issuance interpretation" do
    test "opens the debt as opened and with the full principal as outstanding balance" do
      result = interpret(DebtEvents::Issued.new(principal: 100, at: Date.new(2025, 6, 15)),
                         given: Debt.new, at: Date.new(2025, 6, 15))

      assert_equal 100.00, result.outstanding_balance
      assert result.open?
      assert_equal Date.new(2025, 6, 15), result.contract_date
      assert_equal Date.new(2025, 6, 15), result.last_event_date
    end
  end

  describe "debt payment interpretation" do
    test "keeps the debt open and reduces the outstanding balance" do
      result = interpret(DebtEvents::PaymentReceived.new(principal: 50, at: Date.new(2025, 6, 15)),
                         given: Debt.new(outstanding_balance: 100, status: :open,
                                         contract_date: Date.new(2024, 6, 15), last_event_date: Date.new(2024, 6, 15)),
                         at: Date.new(2025, 6, 15))

      assert_equal 50.00, result.outstanding_balance
      assert result.open?
      assert_equal Date.new(2024, 6, 15), result.contract_date
      assert_equal Date.new(2025, 6, 15), result.last_event_date
    end

    test "marks the debt repaid when the balance reaches zero" do
      result = interpret(DebtEvents::PaymentReceived.new(principal: 100, at: Date.new(2025, 6, 15)),
                         given: Debt.new(outstanding_balance: 100, status: :open,
                                         contract_date: Date.new(2024, 6, 15), last_event_date: Date.new(2024, 6, 15)),
                         at: Date.new(2025, 6, 15))

      assert_equal 0, result.outstanding_balance
      assert result.repaid?
      assert_equal Date.new(2024, 6, 15), result.contract_date
      assert_equal Date.new(2025, 6, 15), result.last_event_date
    end

    test "results an invalid state after an overpayment" do
      result = interpret(DebtEvents::PaymentReceived.new(principal: 1_000, at: Date.new(2025, 6, 15)),
                         given: Debt.new(outstanding_balance: 100, status: :open,
                                         contract_date: Date.new(2024, 6, 15), last_event_date: Date.new(2024, 6, 15)),
                         at: Date.new(2025, 6, 15))

      refute result.valid?
      assert_includes result.errors[:outstanding_balance], "must be greater than or equal to 0"
    end
  end
end

# app/event_streams/debt_event_stream.rb
class DebtEventStream < Funes::EventStream
  add_transactional_projection DebtProjection
  actual_time_attribute :at
end

# [tests] test/event_streams/debt_event_stream_test.rb
class DebtEventStreamTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  t1 = Date.new(2024, 6, 15)
  t2 = Date.new(2024, 9, 15)
  t3 = Date.new(2024, 12, 15)

  describe "debt issuance" do
    test "creates a record to persist the projection state" do
      assert_difference -> { Funes::EventEntry.count }, 1 do
        assert_difference -> { Debt.count }, 1 do
          DebtEventStream.for("d01").append(DebtEvents::Issued.new(principal: 100, at: t1))
        end
      end

      persisted_state = Debt.find("d01")
      assert persisted_state.open?
      assert_equal 100, persisted_state.outstanding_balance
      assert_equal t1, persisted_state.contract_date
      assert_equal t1, persisted_state.last_event_date
    end
  end

  describe "debt simple payment flow" do
    before { DebtEventStream.for("d02").append(DebtEvents::Issued.new(principal: 100, at: t1)) }

    test "keeps the single record to persist the projection state" do
      assert_difference -> { Funes::EventEntry.count }, 1 do
        assert_no_difference -> { Debt.count } do
          DebtEventStream.for("d02").append(DebtEvents::PaymentReceived.new(principal: 50, at: t2))
        end
      end

      persisted_state = Debt.find("d02")
      assert persisted_state.open?
      assert_equal 50, persisted_state.outstanding_balance
      assert_equal t1, persisted_state.contract_date
      assert_equal t2, persisted_state.last_event_date
    end
  end

  describe "failure on debt simple payment" do
    before { DebtEventStream.for("d03").append(DebtEvents::Issued.new(principal: 100, at: t1)) }

    test "rejects the payment and rolls back the event when it would overdraw the balance" do
      overpayment_event = DebtEvents::PaymentReceived.new(principal: 500, at: t2)

      assert_no_difference -> { Funes::EventEntry.count } do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          DebtEventStream.for("d03").append(overpayment_event)
        end
        assert_match(/Outstanding balance/, error.message)
      end

      refute overpayment_event.persisted?
    end
  end

  describe "debt repayment flow" do
    describe "with single payment" do
      before { DebtEventStream.for("d04").append(DebtEvents::Issued.new(principal: 100, at: t1)) }

      test "marks the persisted state repaid when one payment covers the whole principal" do
        assert_difference -> { Funes::EventEntry.count }, 1 do
          assert_no_difference -> { Debt.count } do
            DebtEventStream.for("d04").append(DebtEvents::PaymentReceived.new(principal: 100, at: t2))
          end
        end

        persisted_state = Debt.find("d04")
        assert persisted_state.repaid?
        assert persisted_state.outstanding_balance.zero?
        assert_equal t1, persisted_state.contract_date
        assert_equal t2, persisted_state.last_event_date
      end
    end

    describe "with multiple payments" do
      before do
        stream = DebtEventStream.for("d05")
        stream.append(DebtEvents::Issued.new(principal: 100, at: t1))
        stream.append(DebtEvents::PaymentReceived.new(principal: 50, at: t2))
      end

      test "marks the persisted state repaid when the final payment zeroes the balance" do
        assert_difference -> { Funes::EventEntry.count }, 1 do
          assert_no_difference -> { Debt.count } do
            DebtEventStream.for("d05").append(DebtEvents::PaymentReceived.new(principal: 50, at: t3))
          end
        end

        persisted_state = Debt.find("d05")
        assert persisted_state.repaid?
        assert persisted_state.outstanding_balance.zero?
        assert_equal t1, persisted_state.contract_date
        assert_equal t3, persisted_state.last_event_date
      end
    end
  end
end
