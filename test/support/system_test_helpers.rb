# frozen_string_literal: true

# Shared helpers for system tests. Included in ApplicationSystemTestCase
# so all system tests can opt-in to these methods without defining them locally.
module SystemTestHelpers
  # Purge all Solid Queue tables in FK-safe order. Call this in setup/teardown
  # for tests that interact with job queues (e.g., dashboard tests).
  def purge_solid_queue_tables
    [
      ::SolidQueue::RecurringExecution,
      ::SolidQueue::RecurringTask,
      ::SolidQueue::ClaimedExecution,
      ::SolidQueue::FailedExecution,
      ::SolidQueue::BlockedExecution,
      ::SolidQueue::ScheduledExecution,
      ::SolidQueue::ReadyExecution,
      ::SolidQueue::Process,
      ::SolidQueue::Pause,
      ::SolidQueue::Job
    ].each do |model|
      next unless model.table_exists?

      model.delete_all
    end
  end

  # Seed Solid Queue with representative job data for dashboard testing.
  # Creates one ready job, one scheduled job, one failed job, and one pause.
  def seed_queue_activity(source: nil)
    fetch_queue = SourceMonitor.queue_name(:fetch)

    SolidQueue::Job.create!(
      queue_name: fetch_queue,
      class_name: "SourceMonitor::FetchFeedJob",
      arguments: []
    )

    SolidQueue::Job.create!(
      queue_name: fetch_queue,
      class_name: "SourceMonitor::FetchFeedJob",
      arguments: [],
      scheduled_at: 10.minutes.from_now
    )

    failed_job = SolidQueue::Job.create!(
      queue_name: fetch_queue,
      class_name: "SourceMonitor::FetchFeedJob",
      arguments: []
    )
    failed_job.ready_execution&.destroy!
    SolidQueue::FailedExecution.create!(job: failed_job, error: "RuntimeError: boom")

    SolidQueue::Pause.create!(queue_name: fetch_queue)
  end

  # Apply turbo stream broadcast messages to the current Capybara page by
  # injecting the HTML via JavaScript. Handles Hash payloads, raw strings,
  # and Nokogiri nodes.
  def apply_turbo_stream_messages(messages)
    Array(messages).each do |payload|
      turbo_nodes =
        case payload
        when Nokogiri::XML::Node
          [ payload ]
        else
          message = payload.is_a?(Hash) ? payload["message"] : payload
          next if message.blank?

          parse_turbo_streams(message)
        end

      turbo_nodes.each do |node|
        action = node.attributes["action"]&.value
        target = node.attributes["target"]&.value
        html = node.at_css("template")&.children&.map(&:to_s)&.join
        next if action.blank? || target.blank? || html.blank?

        case action
        when "replace"
          page.execute_script(
            "const target = document.getElementById(arguments[0]); if (target) { target.outerHTML = arguments[1]; }",
            target,
            html
          )
        when "append"
          page.execute_script(
            "const target = document.getElementById(arguments[0]); if (target) { target.insertAdjacentHTML('beforeend', arguments[1]); }",
            target,
            html
          )
        when "prepend"
          page.execute_script(
            "const target = document.getElementById(arguments[0]); if (target) { target.insertAdjacentHTML('afterbegin', arguments[1]); }",
            target,
            html
          )
        end
      end
    end
  end

  # Parse a turbo stream HTML string into an array of Nokogiri turbo-stream nodes.
  def parse_turbo_streams(message)
    document = Nokogiri::XML(message)
    document.css("turbo-stream").map do |node|
      action = node.attributes["action"]&.value
      target = node.attributes["target"]&.value
      html = node.at_css("template")&.children&.map(&:to_s)&.join
      next if action.blank? || target.blank? || html.blank?

      transformed = Nokogiri::XML::Element.new("turbo-stream", document)
      transformed["action"] = action
      transformed["target"] = target
      template = Nokogiri::XML::Element.new("template", document)
      template.inner_html = html
      transformed.add_child(template)
      transformed
    end.compact
  end

  # Assert that items appear in a specific order within the items table.
  # Pass an array of expected titles in display order.
  def assert_item_order(expected)
    within "turbo-frame#source_monitor_items_table" do
      expected.each_with_index do |title, index|
        assert_selector :xpath,
          format(".//tbody/tr[%<row>d]/td[1]", row: index + 1),
          text: /\A#{Regexp.escape(title)}/
      end
    end
  end
end
