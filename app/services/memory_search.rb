# Service for advanced memory search with filtering and ranking
class MemorySearch
  attr_reader :space, :query, :filters, :options

  # Default search options
  DEFAULTS = {
    limit: 20,
    offset: 0,
    order_by: :relevance,
    order_direction: :desc
  }.freeze

  # Initialize with search parameters
  # @param space [Space] The space to search within
  # @param query [String] The search query
  # @param filters [Hash] Optional filters (type:, status:, tags:, etc.)
  # @param options [Hash] Search options (limit:, offset:, order_by:)
  def initialize(space:, query:, filters: {}, options: {})
    @space = space
    @query = query.to_s.strip
    @filters = filters
    @options = DEFAULTS.merge(options)
  end

  # Execute the search and return results
  # @return [SearchResult] Object containing results and metadata
  def execute
    return empty_result if query.blank? && filters.blank?

    scope = build_scope
    scope = apply_filters(scope)
    scope = apply_search(scope)
    scope = apply_ordering(scope)
    scope = apply_pagination(scope)

    results = scope.to_a

    SearchResult.new(
      records: results,
      query: query,
      total_count: count_total,
      page: page_number,
      per_page: per_page,
      filters_applied: filters,
      execution_time_ms: measure_execution { results }
    )
  end

  # Quick search - returns just the records
  def self.quick(space:, query:, limit: 10)
    new(space: space, query: query, options: { limit: limit }).execute.records
  end

  # Search by type
  def self.by_type(space:, type:, limit: 20)
    new(space: space, query: "", filters: { type: type }, options: { limit: limit }).execute.records
  end

  # Search recent memories
  def self.recent(space:, limit: 10)
    space.memories.active.recent.limit(limit)
  end

  # Find memories related to a specific conversation
  def self.for_conversation(conversation)
    space = conversation.council&.space
    return [] unless space

    space.memories.where(source: conversation).ordered
  end

  # Build a memory graph - find related memories
  def self.related(memory, limit: 5)
    return [] unless memory.space

    # Find memories with similar content (simple approach)
    # In production, this could use vector similarity search
    words = memory.title.downcase.split(/\s+/).reject { |w| w.length < 4 }

    return [] if words.empty?

    # Build query from title words
    query = words.join(" OR ")

    new(space: memory.space, query: query, options: { limit: limit })
      .execute
      .records
      .reject { |m| m.id == memory.id }
  end

  private

  def build_scope
    space.memories.includes(:created_by, :source)
  end

  def apply_filters(scope)
    scope = scope.active unless filters[:include_archived]

    if filters[:type].present?
      scope = scope.by_type(filters[:type])
    end

    if filters[:status].present?
      scope = scope.where(status: filters[:status])
    end

    if filters[:tags].present?
      # Search within metadata tags
      tags = Array(filters[:tags])
      scope = scope.where("metadata @> ?", { tags: tags }.to_json)
    end

    if filters[:created_after].present?
      scope = scope.where("created_at >= ?", filters[:created_after])
    end

    if filters[:created_before].present?
      scope = scope.where("created_at <= ?", filters[:created_before])
    end

    if filters[:source_type].present?
      scope = scope.where(source_type: filters[:source_type])
    end

    if filters[:created_by_id].present?
      scope = scope.where(created_by_id: filters[:created_by_id])
    end

    scope
  end

  def apply_search(scope)
    return scope if query.blank?

    # Search in title (case-insensitive)
    # Note: Content search is limited due to encryption
    scope = scope.where("title ILIKE ?", "%#{sanitize_like(query)}%")

    scope
  end

  def apply_ordering(scope)
    case options[:order_by]
    when :relevance
      # Simple relevance: exact matches first, then partial
      scope.order(Arel.sql("CASE WHEN title ILIKE '#{sanitize_sql(query)}' THEN 0 ELSE 1 END, updated_at DESC"))
    when :created_at
      scope.order(created_at: options[:order_direction])
    when :updated_at
      scope.order(updated_at: options[:order_direction])
    when :title
      scope.order(title: options[:order_direction])
    else
      scope.ordered
    end
  end

  def apply_pagination(scope)
    scope.limit(options[:limit]).offset(options[:offset])
  end

  def count_total
    # Get total count without pagination
    count_scope = build_scope
    count_scope = apply_filters(count_scope)
    count_scope = apply_search(count_scope)
    count_scope.count
  end

  def page_number
    (options[:offset].to_i / options[:limit].to_i) + 1
  end

  def per_page
    options[:limit]
  end

  def empty_result
    SearchResult.new(
      records: [],
      query: query,
      total_count: 0,
      page: 1,
      per_page: per_page,
      filters_applied: filters,
      execution_time_ms: 0
    )
  end

  def measure_execution
    start_time = Time.current
    result = yield
    end_time = Time.current

    ((end_time - start_time) * 1000).round(2)
  end

  def sanitize_like(str)
    str.gsub(/[%_]/, "\\%" => "%", "\\_" => "_")
  end

  def sanitize_sql(str)
    str.gsub(/['\\]/, "\\" => "\\\\", "'" => "\\'")
  end

  # Value object for search results
  class SearchResult
    attr_reader :records, :query, :total_count, :page, :per_page,
                :filters_applied, :execution_time_ms

    def initialize(records:, query:, total_count:, page:, per_page:,
                   filters_applied:, execution_time_ms:)
      @records = records
      @query = query
      @total_count = total_count
      @page = page
      @per_page = per_page
      @filters_applied = filters_applied
      @execution_time_ms = execution_time_ms
    end

    def total_pages
      (total_count.to_f / per_page).ceil
    end

    def has_next_page?
      page < total_pages
    end

    def has_previous_page?
      page > 1
    end

    def offset
      (page - 1) * per_page
    end

    def empty?
      records.empty?
    end

    def any?
      records.any?
    end

    def to_h
      {
        records: records.map(&:to_json),
        query: query,
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages,
        filters_applied: filters_applied,
        execution_time_ms: execution_time_ms
      }
    end
  end
end
