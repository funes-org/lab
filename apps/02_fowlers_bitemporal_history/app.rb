require_relative "../support/boot"

# app/models/salary_state.rb
class SalaryState
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :monthly_salary, :decimal
  attribute :since,  :date
end

module Employee
  # app/models/employee/salary_set.rb
  class SalarySet < Funes::Event
    attribute :new_monthly_salary, :decimal
    attribute :at, :date
  end
end

# app/projections/salary_state_projection.rb
class SalaryStateProjection < Funes::Projection
  materialization_model SalaryState

  interpretation_for Employee::SalarySet do |state, event, at|
    state.assign_attributes(monthly_salary: event.new_monthly_salary, since: at)
    state
  end
end

# [test] tests/projections/salary_state_projection_test.rb
class SalaryStateProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include Funes::ProjectionTestHelper

  projection SalaryStateProjection

  describe "how the state is handled at the first event interpretation" do
    test "interprets a salary set over a blank state" do
      materialized_state = interpret(Employee::SalarySet.new(new_monthly_salary: 100, at: Date.today),
                                     given: SalaryState.new, at: Date.today)

      assert_equal 100, materialized_state.monthly_salary
      assert_equal Date.today, materialized_state.since
    end
  end

  describe "how the state is handled when the previous state is already hydrated" do
    test "a later salary set replaces the previously hydrated salary" do
      materialized_state = interpret(Employee::SalarySet.new(new_monthly_salary: 150, at: Date.today),
                                     given: SalaryState.new(monthly_salary: 100, since: 1.year.ago),
                                     at: Date.today)

      assert_equal 150, materialized_state.monthly_salary
      assert_equal Date.today, materialized_state.since
    end
  end
end

# app/event_streams/employee_history_event_stream.rb
class EmployeeHistoryEventStream < Funes::EventStream
  actual_time_attribute :at
end

# [test] tests/event_streams/employee_history_event_stream_test.rb
class EmployeeHistoryEventStreamTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  before do
    travel_to(Date.new(2021, 1, 1)) do
      EmployeeHistoryEventStream.for("sally").append(Employee::SalarySet.new(new_monthly_salary: 6000, at: Date.today))
    end

    travel_to(Date.new(2021, 3, 15)) do
      EmployeeHistoryEventStream
        .for("sally").append(Employee::SalarySet.new(new_monthly_salary: 6500, at: Date.new(2021, 2, 15)))
    end

    travel_to(Date.new(2021, 4, 5)) do
      EmployeeHistoryEventStream
        .for("sally").append(Employee::SalarySet.new(new_monthly_salary: 6400, at: Date.new(2021, 2, 15)))
    end
  end

  # Fowler's sally.salaryAt(actualDate, recordDate)
  def salary_at(actual_date, record_date)
    EmployeeHistoryEventStream
      .for("sally")
      .projected_with(SalaryStateProjection, as_of: record_date, at: actual_date)
      .monthly_salary
  end

  describe "Sally's actual history as seen from each record date" do
    test "on feb 25 payroll still sees 6000 because the feb 15 raise has not been reported yet" do
      assert_equal 6000, salary_at(Date.new(2021, 1, 25), Date.new(2021, 2, 25))
      assert_equal 6000, salary_at(Date.new(2021, 2, 25), Date.new(2021, 2, 25))
    end

    test "the raise reported on mar 15 retroactively rewrites actual history back to feb 15" do
      assert_equal 6000, salary_at(Date.new(2021, 1, 25), Date.new(2021, 3, 25))
      assert_equal 6500, salary_at(Date.new(2021, 2, 25), Date.new(2021, 3, 25))
      assert_equal 6500, salary_at(Date.new(2021, 3, 25), Date.new(2021, 3, 25))
    end

    test "the apr 5 correction supersedes the raise with 6400 and leaves january untouched" do
      assert_equal 6000, salary_at(Date.new(2021, 1, 25), Date.new(2021, 4, 25))
      assert_equal 6400, salary_at(Date.new(2021, 2, 25), Date.new(2021, 4, 25))
      assert_equal 6400, salary_at(Date.new(2021, 3, 25), Date.new(2021, 4, 25))
    end
  end
end
