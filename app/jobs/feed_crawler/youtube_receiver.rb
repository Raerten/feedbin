module FeedCrawler
  class YoutubeReceiver
    include Sidekiq::Worker
    sidekiq_options queue: :parse

    def perform(data)
      ids = data["entries"].map { |entry| entry.safe_dig("data", "youtube_video_id") }
      embeds = Embed.youtube_video.where(provider_id: ids).index_by(&:provider_id)

      data["entries"].map do |entry|
        id = entry.safe_dig("data", "youtube_video_id")
        if embed = embeds[id]
          content = embed.data.safe_dig("snippet", "description")

          if content.present? && entry.safe_dig("content").blank?
            entry["content"] = content
          end

          unless embed.duration_in_seconds == 0
            entry["embed_duration"] = embed.duration_in_seconds
          end
        end
      end

      Receiver.new.perform(data)
    end

  end
end