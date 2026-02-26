# frozen_string_literal: true

def backfill_resolve_source_scope
  if ENV["SOURCE_IDS"].present?
    ENV["SOURCE_IDS"].split(",").map(&:strip).map(&:to_i).reject(&:zero?)
  elsif ENV["SOURCE_ID"].present?
    id = ENV["SOURCE_ID"].to_i
    id.positive? ? [ id ] : nil
  end
end

namespace :source_monitor do
  desc "Backfill word counts for existing item_content records. " \
       "Env vars: SOURCE_ID, SOURCE_IDS (comma-separated), BATCH_SIZE (default 500)."
  task backfill_word_counts: :environment do
    batch_size = (ENV["BATCH_SIZE"] || 500).to_i
    source_ids = backfill_resolve_source_scope
    sanitizer = ActionView::Base.full_sanitizer

    # Phase 1: Batch-create ItemContent for items with feed content but no ItemContent
    items_scope = SourceMonitor::Item
      .where.not(content: [ nil, "" ])
      .where.missing(:item_content)
    items_scope = items_scope.where(source_id: source_ids) if source_ids

    created = 0
    now = Time.current

    items_scope.select(:id, :content).find_in_batches(batch_size: batch_size) do |batch|
      records = batch.filter_map do |item|
        next if item.content.blank?

        stripped = sanitizer.sanitize(item.content)
        word_count = stripped.present? ? stripped.split.size : nil

        { item_id: item.id, feed_word_count: word_count, created_at: now, updated_at: now }
      end

      SourceMonitor::ItemContent.insert_all(records) if records.any?
      created += records.size
      puts "Phase 1: created #{created} ItemContent records..."
    end
    puts "Phase 1 complete: #{created} records created." if created > 0

    # Phase 2: Batch-recompute word counts for existing ItemContent
    contents_scope = SourceMonitor::ItemContent
    if source_ids
      contents_scope = contents_scope.joins(:item).where(SourceMonitor::Item.table_name => { source_id: source_ids })
    end

    total = contents_scope.count
    processed = 0
    updated = 0

    contents_scope.includes(:item).find_in_batches(batch_size: batch_size) do |batch|
      updates = batch.filter_map do |content|
        feed_content = content.item&.content
        scraped = content.scraped_content

        feed_wc = if feed_content.present?
          stripped = sanitizer.sanitize(feed_content)
          stripped.present? ? stripped.split.size : nil
        end

        scraped_wc = scraped.present? ? scraped.split.size : nil

        next if content.feed_word_count == feed_wc && content.scraped_word_count == scraped_wc

        { id: content.id, item_id: content.item_id, feed_word_count: feed_wc, scraped_word_count: scraped_wc }
      end

      if updates.any?
        SourceMonitor::ItemContent.upsert_all(updates, unique_by: :id, update_only: %i[feed_word_count scraped_word_count])
        updated += updates.size
      end

      processed += batch.size
      puts "Phase 2: #{processed}/#{total} checked, #{updated} updated..."
    end

    puts "Done. Phase 1: #{created} created. Phase 2: #{updated}/#{total} updated."
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
