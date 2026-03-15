# frozen_string_literal: true

# Shared test module for the SourceMonitor::Loggable concern.
#
# Including test classes must define:
#   build_loggable(overrides = {}) -> returns an unsaved instance of the concrete model
#
# Example:
#   class FetchLogTest < ActiveSupport::TestCase
#     include SharedLoggableTests
#
#     def build_loggable(overrides = {})
#       SourceMonitor::FetchLog.new({ source: @source, started_at: Time.current }.merge(overrides))
#     end
#   end
module SharedLoggableTests
  extend ActiveSupport::Concern

  included do
    test "loggable: validates presence of started_at" do
      record = build_loggable(started_at: nil)

      assert_not record.valid?
      assert_includes record.errors[:started_at], "can't be blank"
    end

    test "loggable: validates duration_ms is non-negative" do
      record = build_loggable(duration_ms: -1)

      assert_not record.valid?
      assert_includes record.errors[:duration_ms], "must be greater than or equal to 0"
    end

    test "loggable: allows nil duration_ms" do
      record = build_loggable(duration_ms: nil)
      record.valid? # run validations

      assert_not record.errors[:duration_ms].any?,
        "duration_ms should allow nil values"
    end

    test "loggable: metadata defaults to empty hash" do
      record = build_loggable

      assert_equal({}, record.metadata)
    end

    test "loggable: recent scope orders by started_at desc" do
      klass = build_loggable.class

      older = build_loggable(started_at: 10.minutes.ago)
      older.save!
      newer = build_loggable(started_at: 1.minute.ago)
      newer.save!

      scoped = klass.where(id: [older.id, newer.id]).recent
      assert_equal [newer, older], scoped.to_a
    end

    test "loggable: successful scope filters by success true" do
      klass = build_loggable.class

      success_log = build_loggable(success: true, started_at: 2.minutes.ago)
      success_log.save!
      failure_log = build_loggable(success: false, started_at: 1.minute.ago)
      failure_log.save!

      scoped = klass.where(id: [success_log.id, failure_log.id])
      assert_includes scoped.successful, success_log
      assert_not_includes scoped.successful, failure_log
    end

    test "loggable: failed scope filters by success false" do
      klass = build_loggable.class

      success_log = build_loggable(success: true, started_at: 2.minutes.ago)
      success_log.save!
      failure_log = build_loggable(success: false, started_at: 1.minute.ago)
      failure_log.save!

      scoped = klass.where(id: [success_log.id, failure_log.id])
      assert_includes scoped.failed, failure_log
      assert_not_includes scoped.failed, success_log
    end

    test "loggable: since scope filters by started_at" do
      klass = build_loggable.class

      old_log = build_loggable(started_at: 2.days.ago)
      old_log.save!
      recent_log = build_loggable(started_at: 1.hour.ago)
      recent_log.save!

      scoped = klass.where(id: [old_log.id, recent_log.id]).since(1.day.ago)
      assert_includes scoped, recent_log
      assert_not_includes scoped, old_log
    end

    test "loggable: before scope filters by started_at" do
      klass = build_loggable.class

      old_log = build_loggable(started_at: 2.days.ago)
      old_log.save!
      recent_log = build_loggable(started_at: 1.hour.ago)
      recent_log.save!

      scoped = klass.where(id: [old_log.id, recent_log.id]).before(1.day.ago)
      assert_includes scoped, old_log
      assert_not_includes scoped, recent_log
    end
  end
end
