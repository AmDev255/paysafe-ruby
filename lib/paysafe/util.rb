# frozen_string_literal: true

module PaySafe
  module Util
    module_function

    def encode(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    # Symbol keys become strings recursively; nil values are dropped at the top level.
    def stringify(params)
      raise InvalidRequestError, "params must be a Hash" unless params.is_a?(Hash)

      deep = lambda { |v|
        if v.is_a?(Hash)
          v.to_h { |k, x| [k.to_s, deep.call(x)] }
        else
          (v.is_a?(Array) ? v.map { |x| deep.call(x) } : v)
        end
      }
      deep.call(params).compact
    end

    def parse_json(text)
      JSON.parse(text, max_nesting: 32)
    rescue JSON::ParserError
      nil
    end
  end
end
