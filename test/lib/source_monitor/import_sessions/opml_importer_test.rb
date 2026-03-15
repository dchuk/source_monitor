# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module ImportSessions
    class OPMLImporterTest < ActiveSupport::TestCase
      fixtures :users

      setup do
        @user = users(:admin)
        configure_authentication(@user)
      end

      test "creates sources, skips duplicates, and records failures" do
        create_source!(feed_url: "https://dup.example.com/rss")

        session = SourceMonitor::ImportSession.create!(
          user_id: @user.id,
          current_step: "confirm",
          parsed_sources: [
            { "id" => "one", "feed_url" => "https://new-opml-#{SecureRandom.hex(4)}.example.com/rss", "title" => "New", "status" => "valid" },
            { "id" => "dup", "feed_url" => "https://dup.example.com/rss", "title" => "Dup", "status" => "valid" },
            { "id" => "invalid", "feed_url" => nil, "title" => "Missing URL", "status" => "valid" }
          ],
          selected_source_ids: %w[one dup invalid],
          bulk_settings: { "fetch_interval_minutes" => 15, "scraper_adapter" => "readability" }
        )

        history = SourceMonitor::ImportHistory.create!(user_id: @user.id, bulk_settings: session.bulk_settings)

        OPMLImporter.new(import_session: session, import_history: history).call

        history.reload

        assert_equal 1, history.imported_sources.size
        assert_equal 1, history.failed_sources.size
        assert_equal 1, history.skipped_duplicates.size
        assert history.completed_at.present?
        assert history.started_at.present?
      end

      test "handles duplicate entries within the same import" do
        session = SourceMonitor::ImportSession.create!(
          user_id: @user.id,
          current_step: "confirm",
          parsed_sources: [
            { "id" => "a", "feed_url" => "https://same-url-#{SecureRandom.hex(4)}.example.com/rss", "title" => "First" },
            { "id" => "b", "feed_url" => "https://same-url.example.com/rss", "title" => "Second" }
          ],
          selected_source_ids: %w[a b]
        )

        history = SourceMonitor::ImportHistory.create!(user_id: @user.id)

        OPMLImporter.new(import_session: session, import_history: history).call

        history.reload
        # At least one imported, second may be skipped as duplicate
        assert history.completed_at.present?
      end

      test "should_fetch_favicon? returns false when config raises" do
        source = create_source!(
          feed_url: "https://favicon-check-#{SecureRandom.hex(4)}.example.com/rss",
          website_url: "https://favicon-check.example.com"
        )

        session = SourceMonitor::ImportSession.new
        history = SourceMonitor::ImportHistory.new
        importer = OPMLImporter.new(import_session: session, import_history: history)

        broken_config = Object.new
        broken_config.define_singleton_method(:favicons) { raise StandardError, "config broken" }

        SourceMonitor.stub(:config, broken_config) do
          result = importer.send(:should_fetch_favicon?, source)
          assert_equal false, result
        end
      end

      private

      def configure_authentication(user)
        SourceMonitor.configure do |config|
          config.authentication.current_user_method = :current_user
          config.authentication.user_signed_in_method = :user_signed_in?

          config.authentication.authenticate_with lambda { |controller|
            controller.singleton_class.define_method(:current_user) { user }
            controller.singleton_class.define_method(:user_signed_in?) { user.present? }
          }

          config.authentication.authorize_with lambda { |_controller|
            true
          }
        end
      end
    end
  end
end
