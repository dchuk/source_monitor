# frozen_string_literal: true

namespace :source_monitor do
  desc "Backfill word counts for existing item_content records."
  task backfill_word_counts: :environment do
    # Phase 1: Create ItemContent for items with feed content but no ItemContent
    items_needing_content = SourceMonitor::Item
      .where.not(content: [ nil, "" ])
      .where.missing(:item_content)

    created = 0
    items_needing_content.find_each do |item|
      item.ensure_feed_content_record
      created += 1
      puts "Created #{created} missing ItemContent records..." if (created % 100).zero?
    end
    puts "Created #{created} ItemContent records for feed-only items." if created > 0

    # Phase 2: Recompute word counts for all existing ItemContent
    total = SourceMonitor::ItemContent.count
    processed = 0

    SourceMonitor::ItemContent.find_each do |content|
      content.save!
      processed += 1
      puts "Processed #{processed}/#{total} records..." if (processed % 100).zero?
    end

    puts "Done. Backfilled word counts for #{processed} records (#{created} newly created)."
  end

  namespace :cleanup do
    desc "Run retention pruning across sources. Accepts SOURCE_IDS and SOFT_DELETE env vars."
    task items: :environment do
      options = {}

      if ENV["SOURCE_IDS"].present?
        options[:source_ids] = ENV["SOURCE_IDS"]
      elsif ENV["SOURCE_ID"].present?
        options[:source_id] = ENV["SOURCE_ID"]
      end

      if ENV.key?("SOFT_DELETE")
        options[:soft_delete] = ENV["SOFT_DELETE"]
      end

      SourceMonitor::ItemCleanupJob.perform_now(options)
    end

    desc "Purge old fetch and scrape logs. Override defaults via FETCH_LOG_DAYS and SCRAPE_LOG_DAYS env vars."
    task logs: :environment do
      options = {}
      options[:fetch_logs_older_than_days] = ENV["FETCH_LOG_DAYS"] if ENV["FETCH_LOG_DAYS"].present?
      options[:scrape_logs_older_than_days] = ENV["SCRAPE_LOG_DAYS"] if ENV["SCRAPE_LOG_DAYS"].present?

      SourceMonitor::LogCleanupJob.perform_now(options)
    end
  end
end
