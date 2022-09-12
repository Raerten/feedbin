class FeedParser
  include Sidekiq::Worker
  sidekiq_options queue: "feed_parser_#{Socket.gethostname}", retry: false

  def perform(feed_id, feed_url, path, encoding = nil)
    @feed_id = feed_id
    @feed_url = feed_url
    @path = path
    @encoding = encoding

    filter = EntryFilter.new(parsed_feed.entries)
    entries = filter.filter

    save(parsed_feed.to_feed, entries) unless entries.empty?
    clear_feed_status!

    filter.fingerprint_entries
  rescue Feedkit::NotFeed => exception
    Sidekiq.logger.info "Feedkit::NotFeed: id=#{@feed_id} url=#{@feed_url}"
    record_feed_error!(exception)
  ensure
    cleanup
  end

  private

  def parsed_feed
    @parsed_feed ||= begin
      body = File.read(@path, binmode: true)
      Feedkit::Parser.parse!(body, url: @feed_url, encoding: @encoding)
    end
  end

  def cleanup
    File.unlink(@path) rescue Errno::ENOENT
  end

  def save(feed, entries)
    Sidekiq::Client.push(
      "class" => "FeedRefresherReceiver",
      "queue" => "feed_refresher_receiver",
      "args" => [{
        "feed" => feed.merge({"id" => @feed_id}),
        "entries" => entries
      }]
    )
  end

  def clear_feed_status!
    Sidekiq::Client.push(
      "args" => [@feed_id],
      "class" => "Crawler::Refresher::FeedStatusUpdate",
      "queue" => "feed_downloader_critical"
    )
  end

  def record_feed_error!(exception)
    exception = JSON.dump({date: Time.now.to_i, class: exception.class, message: exception.message, status: nil})
    Sidekiq::Client.push(
      "args" => [@feed_id, exception],
      "class" => "Crawler::Refresher::FeedStatusUpdate",
      "queue" => "feed_downloader_critical"
    )
  end
end

class FeedParserCritical
  include Sidekiq::Worker
  sidekiq_options queue: "feed_parser_critical_#{Socket.gethostname}", retry: false
  def perform(*args)
    FeedParser.new.perform(*args)
  end
end
