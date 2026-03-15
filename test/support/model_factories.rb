# frozen_string_literal: true

# Shared factory helpers for SourceMonitor engine tests.
#
# Included in ActiveSupport::TestCase via test_helper.rb so every test
# gets these methods automatically.  Each helper follows the same pattern:
# sensible defaults, keyword overrides, save!(validate: false) for speed,
# SecureRandom for uniqueness.
#
# == Factories
#
#   create_source!(attributes = {})
#     Creates a SourceMonitor::Source.
#     Defaults: name, feed_url (unique), website_url, fetch_interval_minutes,
#     scraper_adapter.
#
#   create_item!(source:, **overrides)
#     Creates a SourceMonitor::Item belonging to +source+.
#     Defaults: guid (uuid), url (unique), title.
#
#   create_fetch_log!(source:, **overrides)
#     Creates a SourceMonitor::FetchLog for +source+.
#     Defaults: started_at, success (true), items_created/updated/failed (0).
#
#   create_scrape_log!(item:, source: nil, **overrides)
#     Creates a SourceMonitor::ScrapeLog. Derives +source+ from +item+ if
#     not given.
#     Defaults: started_at, scraper_adapter.
#
#   create_health_check_log!(source:, **overrides)
#     Creates a SourceMonitor::HealthCheckLog for +source+.
#     Defaults: started_at, success (true), http_status (200), duration_ms.
#
#   create_log_entry!(source:, loggable:, **overrides)
#     Creates a SourceMonitor::LogEntry for +source+ and polymorphic +loggable+.
#     Defaults: started_at, success (true).
#
#   create_item_content!(item:, **overrides)
#     Creates a SourceMonitor::ItemContent for +item+.
#     Defaults: feed_word_count (50).
#
module ModelFactories
  private

  def create_source!(attributes = {})
    defaults = {
      name: "Test Source",
      feed_url: "https://example.com/feed-#{SecureRandom.hex(4)}.xml",
      website_url: "https://example.com",
      fetch_interval_minutes: 60,
      scraper_adapter: "readability"
    }

    source = SourceMonitor::Source.new(defaults.merge(attributes))
    source.save!(validate: false)
    source
  end

  def create_item!(source:, **overrides)
    defaults = {
      source: source,
      guid: SecureRandom.uuid,
      url: "https://example.com/#{SecureRandom.hex(6)}",
      title: "Test Item"
    }

    item = SourceMonitor::Item.new(defaults.merge(overrides))
    item.save!(validate: false)
    item
  end

  def create_fetch_log!(source:, **overrides)
    defaults = {
      source: source,
      started_at: Time.current,
      success: true,
      items_created: 0,
      items_updated: 0,
      items_failed: 0
    }

    SourceMonitor::FetchLog.create!(defaults.merge(overrides))
  end

  def create_scrape_log!(item:, source: nil, **overrides)
    defaults = {
      source: source || item.source,
      item: item,
      started_at: Time.current,
      scraper_adapter: "readability"
    }

    SourceMonitor::ScrapeLog.create!(defaults.merge(overrides))
  end

  def create_health_check_log!(source:, **overrides)
    defaults = {
      source: source,
      started_at: Time.current,
      success: true,
      http_status: 200,
      duration_ms: 100
    }

    SourceMonitor::HealthCheckLog.create!(defaults.merge(overrides))
  end

  def create_log_entry!(source:, loggable:, **overrides)
    defaults = {
      source: source,
      loggable: loggable,
      started_at: Time.current,
      success: true
    }

    SourceMonitor::LogEntry.create!(defaults.merge(overrides))
  end

  def create_item_content!(item:, **overrides)
    defaults = {
      item: item,
      feed_word_count: 50
    }

    SourceMonitor::ItemContent.create!(defaults.merge(overrides))
  end
end
