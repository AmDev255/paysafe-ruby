# frozen_string_literal: true

module PaySafe
  # One page of a cursor-paginated list. Enumerate it for its items; auto_paging_each walks every page.
  class Page
    include Enumerable

    attr_reader :data, :next_cursor, :last_response

    def initialize(data, has_more, next_cursor, last_response, fetch_next)
      @data = data
      @has_more = has_more
      @next_cursor = next_cursor
      @last_response = last_response
      @fetch_next = fetch_next
    end

    def self.from_response(response, klass, &fetch_next)
      root = response.json
      items = Array(root&.dig("data")).grep(Hash).map { |e| klass.from(e, response) }
      cursor = root&.dig("next_cursor")
      new(items, root&.dig("has_more") == true, cursor.is_a?(String) ? cursor : nil, response, fetch_next)
    end

    def has_more?
      @has_more
    end

    def each(&)
      @data.each(&)
    end

    def size
      @data.size
    end
    alias length size

    def [](index)
      @data[index]
    end

    # The following page, or nil when this was the last one.
    def next_page
      return nil if !@has_more || @next_cursor.nil? || @fetch_next.nil?

      @fetch_next.call(@next_cursor)
    end

    # Every item on this page and all following pages, fetched lazily.
    def auto_paging_each(&)
      return enum_for(:auto_paging_each) unless block_given?

      page = self
      while page
        page.each(&)
        page = page.next_page
      end
    end
  end
end
