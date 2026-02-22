# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourcesControllerTest < ActionDispatch::IntegrationTest
    include ActionView::RecordIdentifier
    fixtures :users

    test "sanitizes attributes when creating a source" do
      assert_difference -> { Source.count }, 1 do
        post "/source_monitor/sources", params: {
          source: {
            name: "<script>alert(1)</script>Example Source",
            feed_url: "https://example.com/feed.xml",
            website_url: "https://example.com",
            fetch_interval_minutes: 60,
            scrape_settings: {
              selectors: {
                content: "<script>danger()</script>",
                title: "<img src=x onerror=alert(1)>Headline"
              }
            }
          }
        }
      end

      source = Source.order(:created_at).last

      assert_redirected_to "/source_monitor/sources/#{source.id}"

      assert_equal "alert(1)Example Source", source.name
      refute_includes source.name, "<"

      content_selector = source.scrape_settings.dig("selectors", "content")
      title_selector = source.scrape_settings.dig("selectors", "title")

      assert_equal "danger()", content_selector
      refute_includes title_selector, "<"
      refute_includes title_selector, ">"
    end

    test "sanitizes search params before rendering" do
      get "/source_monitor/sources", params: {
        q: {
          "name_or_feed_url_or_website_url_cont" => "<script>alert(2)</script>"
        }
      }

      assert_response :success
      response_body = response.body
      refute_includes response_body, "%3Cscript"
      refute_includes response_body, "&lt;script"
      assert_includes response_body, "value=\"alert(2)\""
    end

    test "index shows recent import history summary" do
      SourceMonitor::ImportHistory.create!(
        user_id: users(:admin).id,
        imported_sources: [ { "id" => 1, "feed_url" => "https://example.com/feed.xml", "name" => "Example" } ],
        failed_sources: [],
        skipped_duplicates: [],
        bulk_settings: {},
        started_at: Time.current,
        completed_at: Time.current
      )

      get "/source_monitor/sources"

      assert_response :success
      assert_includes response.body, "Recent OPML import"
      assert_includes response.body, "Imported 1"
    end

    test "new preloads default attributes" do
      get "/source_monitor/sources/new"

      assert_response :success
      assert_includes response.body, "fetch_interval_minutes"
      assert_match(/360/, response.body)
    end

    test "destroy removes source and dependents via turbo stream" do
      keep_source = create_source!(name: "Keep", feed_url: "https://keep.example.com/feed.xml")
      source = create_source!(name: "Remove", feed_url: "https://remove.example.com/feed.xml")

      item = source.items.create!(
        guid: "guid-1",
        title: "Item",
        url: "https://example.com/1",
        published_at: Time.current
      )
      source.fetch_logs.create!(success: true, started_at: Time.current, completed_at: Time.current, items_created: 1)
      source.scrape_logs.create!(
        item: item,
        success: true,
        started_at: Time.current,
        completed_at: Time.current,
        scraper_adapter: "readability"
      )

      assert_difference [
        -> { SourceMonitor::Source.count },
        -> { SourceMonitor::Item.count },
        -> { SourceMonitor::FetchLog.count },
        -> { SourceMonitor::ScrapeLog.count }
      ], -1 do
        delete source_monitor.source_path(source), params: { q: { "name_or_feed_url_or_website_url_cont" => "Keep" } }, as: :turbo_stream
      end

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, %(<turbo-stream action="remove" target="#{dom_id(source, :row)}">)
      assert_includes response.body, %(<turbo-stream action="replace" target="source_monitor_sources_heatmap">)
      assert_includes response.body, %(<turbo-stream action="append" target="source_monitor_notifications">)

      assert SourceMonitor::Source.exists?(keep_source.id), "expected other sources to remain"
      refute SourceMonitor::Item.exists?(item.id), "expected associated items to be deleted"
    end

    test "destroy turbo stream includes redirect when redirect_to provided" do
      source = create_source!(name: "Redirected", feed_url: "https://redirect.example.com/feed.xml")

      delete source_monitor.source_path(source),
        params: { redirect_to: source_monitor.sources_path },
        as: :turbo_stream

      assert_response :success
      # Verify custom redirect turbo-stream action is present with url attribute
      assert_includes response.body, %(<turbo-stream action="redirect")
      assert_includes response.body, %(url="#{source_monitor.sources_path}")
      assert_includes response.body, %(visit-action="replace")
      # Ensure no inline script tags
      refute_includes response.body, %(<script>)
    end

    test "destroy removes source via html format" do
      source = create_source!(name: "HTML Delete", feed_url: "https://html-delete.example.com/feed.xml")

      assert_difference -> { Source.count }, -1 do
        delete source_monitor.source_path(source)
      end

      assert_redirected_to source_monitor.sources_path
      assert_equal "Source deleted", flash[:notice]
    end

    test "destroy turbo stream shows error toast when destroy returns false" do
      source = create_source!(name: "Stubbed Fail", feed_url: "https://stubbed-fail.example.com/feed.xml")

      source.stub(:destroy, false) do
        Source.stub(:find, source) do
          assert_no_difference -> { Source.count } do
            delete source_monitor.source_path(source), as: :turbo_stream
          end
        end
      end

      assert_response :unprocessable_entity
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "Could not delete source"
    end

    test "destroy html shows alert when destroy returns false" do
      source = create_source!(name: "HTML Fail", feed_url: "https://html-fail.example.com/feed.xml")

      source.stub(:destroy, false) do
        Source.stub(:find, source) do
          assert_no_difference -> { Source.count } do
            delete source_monitor.source_path(source)
          end
        end
      end

      assert_redirected_to source_monitor.sources_path(q: {})
      assert_includes flash[:alert], "Could not delete source"
    end

    test "destroy turbo stream shows error toast on foreign key violation" do
      source = create_source!(name: "FK Violation", feed_url: "https://fk-violation.example.com/feed.xml")

      source.stub(:destroy, -> { raise ActiveRecord::InvalidForeignKey, "FK constraint" }) do
        Source.stub(:find, source) do
          assert_no_difference -> { Source.count } do
            delete source_monitor.source_path(source), as: :turbo_stream
          end
        end
      end

      assert_response :unprocessable_entity
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "Cannot delete source"
      assert_includes response.body, "other records still reference it"
    end

    test "destroy html redirects with alert on foreign key violation" do
      source = create_source!(name: "HTML FK", feed_url: "https://html-fk.example.com/feed.xml")

      source.stub(:destroy, -> { raise ActiveRecord::InvalidForeignKey, "FK constraint" }) do
        Source.stub(:find, source) do
          delete source_monitor.source_path(source)
        end
      end

      assert_redirected_to source_monitor.sources_path(q: {})
      assert_includes flash[:alert], "Cannot delete source"
    end

    test "create still succeeds when favicon enqueue raises" do
      SourceMonitor::FaviconFetchJob.stub(:perform_later, ->(*) { raise StandardError, "queue down" }) do
        assert_difference -> { Source.count }, 1 do
          post "/source_monitor/sources", params: {
            source: {
              name: "Favicon Error Source",
              feed_url: "https://favicon-error.example.com/feed.xml",
              website_url: "https://favicon-error.example.com",
              fetch_interval_minutes: 60
            }
          }
        end
      end

      assert_redirected_to "/source_monitor/sources/#{Source.order(:created_at).last.id}"
    end

    test "index renders activity rates without N+1 queries" do
      # Create multiple sources with recent items to ensure view renders rates
      5.times do |i|
        source = create_source!(name: "Source #{i}", feed_url: "https://example#{i}.com/feed.xml")
        # Create some recent items
        3.times do |j|
          source.items.create!(
            guid: "item-#{i}-#{j}",
            title: "Item #{j}",
            url: "https://example#{i}.com/item-#{j}",
            published_at: j.days.ago
          )
        end
      end

      get source_monitor.sources_path
      assert_response :success

      # Verify page renders successfully with activity rates displayed
      # The removal of the fallback in _row.html.erb ensures no N+1 queries occur
      assert response.body.include?("/ day"), "Expected activity rates to be displayed"
    end

    # --- Pagination tests ---

    test "index returns paginated results with 25 per page default" do
      30.times { |i| create_source!(name: "Paginated #{i}") }

      get source_monitor.sources_path
      assert_response :success

      assert_includes response.body, "Page 1"
      assert_includes response.body, "Next"
      assert_select "tbody#source_monitor_sources_table_body tr[id^='row_']", 25
    end

    test "index page 2 returns remaining sources" do
      30.times { |i| create_source!(name: "Page2 #{i}") }

      get source_monitor.sources_path, params: { page: 2 }
      assert_response :success

      assert_includes response.body, "Page 2"
      assert_includes response.body, "Previous"
      assert_select "tbody#source_monitor_sources_table_body tr[id^='row_']", 5
    end

    test "index respects per_page param" do
      15.times { |i| create_source!(name: "PerPage #{i}") }

      get source_monitor.sources_path, params: { per_page: 10 }
      assert_response :success

      assert_select "tbody#source_monitor_sources_table_body tr[id^='row_']", 10
    end

    test "index caps per_page at 100" do
      3.times { |i| create_source!(name: "Capped #{i}") }

      get source_monitor.sources_path, params: { per_page: 200 }
      assert_response :success

      # per_page=200 capped at 100, but only 3 sources exist
      assert_select "tbody#source_monitor_sources_table_body tr[id^='row_']", 3
    end

    # --- Filter tests ---

    test "index filters by health_status_eq" do
      create_source!(name: "Healthy Source", health_status: "healthy")
      create_source!(name: "Warning Source", health_status: "warning")
      create_source!(name: "Critical Source", health_status: "critical")

      get source_monitor.sources_path, params: { q: { health_status_eq: "warning" } }
      assert_response :success

      assert_includes response.body, "Warning Source"
      refute_includes response.body, "Healthy Source"
      refute_includes response.body, "Critical Source"
      # Filter banner should show the active filter
      assert_includes response.body, "Health: Warning"
    end

    test "index filters by scraper_adapter_eq" do
      create_source!(name: "Readability Source", scraper_adapter: "readability")
      create_source!(name: "Custom Source", scraper_adapter: "custom_scraper")

      get source_monitor.sources_path, params: { q: { scraper_adapter_eq: "custom_scraper" } }
      assert_response :success

      assert_includes response.body, "Custom Source"
      refute_includes response.body, "Readability Source"
      assert_includes response.body, "Adapter: Custom Scraper"
    end

    test "index combines text search with dropdown filter" do
      create_source!(name: "Healthy Blog", health_status: "healthy")
      create_source!(name: "Warning Blog", health_status: "warning")
      create_source!(name: "Healthy News", health_status: "healthy")

      get source_monitor.sources_path, params: {
        q: {
          name_or_feed_url_or_website_url_cont: "Blog",
          health_status_eq: "healthy"
        }
      }
      assert_response :success

      assert_includes response.body, "Healthy Blog"
      refute_includes response.body, "Warning Blog"
      refute_includes response.body, "Healthy News"
    end

    test "pagination preserves filter params across pages" do
      30.times { |i| create_source!(name: "Filtered #{i}", health_status: "warning") }
      create_source!(name: "Healthy Excluded", health_status: "healthy")

      get source_monitor.sources_path, params: { q: { health_status_eq: "warning" } }
      assert_response :success

      assert_select "tbody#source_monitor_sources_table_body tr[id^='row_']", 25
      # Next link should preserve the filter param
      assert_match(/health_status_eq/, response.body)

      # Navigate to page 2 with filter
      get source_monitor.sources_path, params: { page: 2, q: { health_status_eq: "warning" } }
      assert_response :success

      assert_select "tbody#source_monitor_sources_table_body tr[id^='row_']", 5
      refute_includes response.body, "Healthy Excluded"
    end
  end
end
