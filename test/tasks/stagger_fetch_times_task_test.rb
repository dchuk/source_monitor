# frozen_string_literal: true

require "test_helper"
require "rake"

class StaggerFetchTimesTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("source_monitor:maintenance:stagger_fetch_times")
  end

  test "staggers due sources across the window" do
    task = Rake::Task["source_monitor:maintenance:stagger_fetch_times"]
    task.reenable

    s1 = create_source!(name: "Stagger A", feed_url: "https://stagger-a.test/feed", next_fetch_at: nil)
    s2 = create_source!(name: "Stagger B", feed_url: "https://stagger-b.test/feed", next_fetch_at: 1.hour.ago)
    s3 = create_source!(name: "Stagger C", feed_url: "https://stagger-c.test/feed", next_fetch_at: 30.minutes.ago)

    output = nil
    begin
      ENV["WINDOW_MINUTES"] = "6"
      output = capture_io { task.invoke }.first
    ensure
      ENV.delete("WINDOW_MINUTES")
    end

    assert_match(/Staggered 3 sources across 6 minutes/, output)

    s1.reload
    s2.reload
    s3.reload

    times = [ s1, s2, s3 ].sort_by(&:id).map(&:next_fetch_at)

    assert times[0] < times[1], "First source should be scheduled before second"
    assert times[1] < times[2], "Second source should be scheduled before third"

    spread = times[2] - times[0]
    assert_in_delta 360.0, spread, 1.0, "Total spread should be ~6 minutes (360s)"
  end

  test "skips sources that are not due" do
    task = Rake::Task["source_monitor:maintenance:stagger_fetch_times"]
    task.reenable

    future_source = create_source!(
      name: "Future",
      feed_url: "https://future.test/feed",
      next_fetch_at: 1.hour.from_now
    )

    output = capture_io { task.invoke }.first

    assert_match(/No sources need staggering/, output)
    assert_equal future_source.reload.next_fetch_at.to_i, future_source.next_fetch_at.to_i
  end

  test "skips sources in fetching or queued status" do
    task = Rake::Task["source_monitor:maintenance:stagger_fetch_times"]
    task.reenable

    fetching_source = create_source!(
      name: "Fetching",
      feed_url: "https://fetching.test/feed",
      next_fetch_at: 1.hour.ago,
      fetch_status: "fetching"
    )

    output = capture_io { task.invoke }.first

    assert_match(/No sources need staggering/, output)
  end
end
