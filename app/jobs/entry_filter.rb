class EntryFilter

  def self.filter!(*args, **kwargs)
    new(*args, **kwargs).filter
  end

  def initialize(entries, check_for_updates: true, date_filter: nil)
    @entries = entries
    @check_for_updates = check_for_updates
    @date_filter = date_filter
  end

  def filter
    @filter ||= begin
      @entries.first(300).each_with_object([]) do |entry, array|
        if new?(entry)
          array.push(entry.to_entry)
        elsif @check_for_updates && updated?(entry.public_id, entry.content)
          result = entry.to_entry
          result[:update] = true
          array.push(result)
        end
      end
    end
  end

  def fingerprint_entries
    candidates = @entries.first(300)

    old_fingerprints = $redis[:refresher].with do |redis|
      keys = candidates.map do |entry|
        "f:#{entry.public_id}"
      end

      keys.empty? ? {} : redis.mapped_mget(*keys)
    end

    new_fingerprints = {}
    new_lengths = {}
    entries_map = {}
    old_database_fingerprints = Entry.where(public_id: candidates.map(&:public_id)).pluck(Arel.sql("public_id, REPLACE(fingerprint::text, '-', '')")).to_h

    candidates.each do |entry|
      new_fingerprints["f:#{entry.public_id}"] = entry.fingerprint
      new_lengths[entry.public_id] = entry.content&.length
      entries_map[entry.public_id] = entry
    end

    fingerprint_results = new_fingerprints.each_with_object([]) do |(key, value), array|
      old_value = old_fingerprints[key]
      if old_value.nil?
        array.push(:new)
      elsif old_value != value
        array.push(:updated)
      else
        array.push(:unchanged)
      end
    end

    new_entries = nil
    database_fingerprint_results = new_fingerprints.each_with_object([]) do |(key, value), array|
      key = key.sub("f:", "")
      old_value = old_database_fingerprints[key]
      if !old_database_fingerprints.key?(key) && !saved_entries[key].nil? && saved_entries[key] != 1

        if new_entries.nil?
          entry = entries_map[key]
          new_entries = {public_id: key, title: entry.title, published: entry.published&.iso8601}
        end

        array.push(:new)
      elsif old_database_fingerprints.key?(key) && old_value != value
        array.push(:updated)
      else
        array.push(:unchanged)
      end
    end

    length_results = new_lengths.each_with_object([]) do |(key, value), array|
      old_value = saved_entries[key]
      if old_value.nil?
        array.push(:new)
      elsif old_value != value
        array.push(:updated)
      else
        array.push(:unchanged)
      end
    end


    mismatch = (fingerprint_results.tally[:new].nil? && database_fingerprint_results.tally[:new].present?) ? new_entries : "none"

    Sidekiq.logger.info "fingerprint_results=#{fingerprint_results.tally} database_fingerprint_results=#{database_fingerprint_results.tally}  length_results=#{length_results.tally} mismatch=#{mismatch}"

    return if new_fingerprints.empty?

    $redis[:refresher].with do |redis|
      redis.mapped_mset(new_fingerprints)
    end

    new_fingerprints.transform_keys do |key|
      key.sub("f:", "")
    end
  end

  private

  def new?(entry)
    saved_entries[entry.public_id].nil? && fresh?(entry)
  end

  def updated?(public_id, content)
    length = saved_entries[public_id]
    return false if !length
    return false if !content
    return false if length == 1
    content.length != length
  end

  def saved_entries
    @saved_entries ||= $redis[:refresher].with do |redis|
      keys = @entries.map(&:public_id)
      redis.mapped_mget(*keys).transform_values { |value| value&.to_i }
    end
  end

  def fresh?(entry)
    return true if @date_filter.nil?
    return true if entry.published.nil?
    entry.published > @date_filter
  end
end
