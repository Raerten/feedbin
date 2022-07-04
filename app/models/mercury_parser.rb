class MercuryParser
  attr_reader :url

  def initialize(url, data = nil, user = ENV["EXTRACT_USER"])
    @url = url
    @user = user
    load_data(data) if data
  end

  def self.parse(*args)
    Librato.increment "readability.first_parse"
    new(*args)
  end

  def title
    result["title"]
  end

  def content
    result["content"]
  end

  def author
    result["author"]
  end

  def published
    if result["date_published"]
      Time.parse(result["date_published"])
    end
  rescue
    nil
  end

  def date_published
    result["date_published"]
  end

  def domain
    result["domain"]
  end

  def to_h
    {
      result: result,
      url: url
    }
  end

  def service_url
    @service_url ||= begin
      digest = OpenSSL::Digest.new("sha1")
      signature = OpenSSL::HMAC.hexdigest(digest, ENV["EXTRACT_SECRET"], url)
      base64_url = Base64.urlsafe_encode64(url).delete("\n")
      URI::HTTPS.build({
        host: ENV["EXTRACT_HOST"],
        path: "/parser/#{@user}/#{signature}",
        query: "base64_url=#{base64_url}"
      }).to_s
    end
  end

  private

  def result
    @result ||= begin
      response = HTTP.timeout(write: 20, connect: 20, read: 20).use(:auto_inflate).headers("Accept-Encoding" => "gzip").get(service_url)
      response.parse
    end
  end

  def marshal_dump
    to_h
  end

  def marshal_load(data)
    @result = data[:result]
    @url = data[:url]
  end

  def load_data(data)
    @result = data["result"]
    @url = data["url"]
  end
end
