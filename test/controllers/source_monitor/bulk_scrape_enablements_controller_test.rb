# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class BulkScrapeEnablementsControllerTest < ActionDispatch::IntegrationTest
    fixtures :users

    test "POST create with valid source_ids updates sources and returns success toast" do
      source1 = create_source!(name: "Bulk Enable 1", scraping_enabled: false)
      source2 = create_source!(name: "Bulk Enable 2", scraping_enabled: false)

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [ source1.id, source2.id ] } },
        as: :turbo_stream

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type

      source1.reload
      source2.reload
      assert source1.scraping_enabled?, "expected source1 scraping to be enabled"
      assert source2.scraping_enabled?, "expected source2 scraping to be enabled"

      assert_includes response.body, "Scraping enabled for 2 sources"
      assert_includes response.body, %(<turbo-stream action="redirect")
    end

    test "POST create with empty source_ids returns warning" do
      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [] } },
        as: :turbo_stream

      assert_response :unprocessable_entity
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "No sources selected"
    end

    test "POST create only updates sources where scraping_enabled is false" do
      already_enabled = create_source!(name: "Already Enabled", scraping_enabled: true)
      not_enabled = create_source!(name: "Not Enabled", scraping_enabled: false)

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [ already_enabled.id, not_enabled.id ] } },
        as: :turbo_stream

      assert_response :success

      not_enabled.reload
      assert not_enabled.scraping_enabled?, "expected not_enabled source to be enabled"

      # Only 1 source was actually updated (the one that had scraping_enabled: false)
      assert_includes response.body, "Scraping enabled for 1 source."
    end

    test "POST create sets scraper_adapter to readability" do
      source = create_source!(name: "Adapter Check", scraping_enabled: false)
      # Set adapter to something else to verify it gets overwritten
      source.update_columns(scraper_adapter: "custom")

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [ source.id ] } },
        as: :turbo_stream

      assert_response :success
      source.reload
      assert_equal "readability", source.scraper_adapter
    end

    test "POST create turbo stream returns redirect action" do
      source = create_source!(name: "Redirect Check", scraping_enabled: false)

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [ source.id ] } },
        as: :turbo_stream

      assert_response :success
      assert_includes response.body, %(<turbo-stream action="redirect")
      assert_includes response.body, %(url="#{source_monitor.sources_path}")
    end

    test "POST create via html format redirects with notice" do
      source = create_source!(name: "HTML Bulk", scraping_enabled: false)

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [ source.id ] } }

      assert_redirected_to source_monitor.sources_path
      assert_equal "Scraping enabled for 1 source.", flash[:notice]
    end

    test "POST create via html format with empty source_ids redirects with alert" do
      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [] } }

      assert_redirected_to source_monitor.sources_path
      assert_equal "No sources selected.", flash[:alert]
    end

    test "POST create sets scraper_adapter to the DB column default" do
      source = create_source!(name: "Column Default Check", scraping_enabled: false)
      source.update_columns(scraper_adapter: "custom")

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [ source.id ] } },
        as: :turbo_stream

      assert_response :success
      source.reload
      assert_equal SourceMonitor::Source.column_defaults["scraper_adapter"], source.scraper_adapter
    end

    test "POST create with select_all_pages enables all scrape candidates" do
      source1 = create_source!(name: "Candidate 1", scraping_enabled: false)
      source2 = create_source!(name: "Candidate 2", scraping_enabled: false)
      non_candidate = create_source!(name: "Already Enabled", scraping_enabled: true)

      # Create items with low word count to make source1 and source2 scrape candidates
      item1 = create_item!(source: source1, content: "short content")
      item1.ensure_feed_content_record
      item2 = create_item!(source: source2, content: "also short")
      item2.ensure_feed_content_record

      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { select_all_pages: "true" } },
        as: :turbo_stream

      assert_response :success

      source1.reload
      source2.reload
      non_candidate.reload
      assert source1.scraping_enabled?, "expected source1 scraping to be enabled"
      assert source2.scraping_enabled?, "expected source2 scraping to be enabled"
      assert non_candidate.scraping_enabled?, "non_candidate should remain enabled"
    end

    test "POST create with select_all_pages ignores submitted source_ids" do
      source1 = create_source!(name: "Candidate Only", scraping_enabled: false)
      non_candidate = create_source!(name: "Non Candidate", scraping_enabled: false)

      # Only source1 is a scrape candidate (has item with low word count)
      item = create_item!(source: source1, content: "short content")
      item.ensure_feed_content_record

      # Submit non_candidate in source_ids, but select_all_pages should use DB query instead
      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { select_all_pages: "true", source_ids: [ non_candidate.id ] } },
        as: :turbo_stream

      assert_response :success

      source1.reload
      non_candidate.reload
      assert source1.scraping_enabled?, "expected scrape candidate to be enabled"
      assert_not non_candidate.scraping_enabled?, "non-candidate should not be enabled via select_all_pages"
    end

    test "route POST /bulk_scrape_enablements routes correctly" do
      post source_monitor.bulk_scrape_enablements_path,
        params: { bulk_scrape_enablement: { source_ids: [] } }

      # If routing works, we get a redirect (empty selection handler), not a routing error
      assert_redirected_to source_monitor.sources_path
    end
  end
end
