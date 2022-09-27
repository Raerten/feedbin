class CrawlDataType < ActiveModel::Type::Value
  def type
    :jsonb
  end

  def cast(value)
    CrawlData.new(value) unless value.nil?
  end

  def deserialize(value)
    if String === value
      decoded = ::ActiveSupport::JSON.decode(value) rescue nil
      CrawlData.new(decoded) unless decoded.nil?
    else
      super
    end
  end

  def serialize(value)
    case value
    when Array, Hash
      ::ActiveSupport::JSON.encode(value)
    when CrawlData
      ::ActiveSupport::JSON.encode(value.to_h)
    else
      super
    end
  end
end