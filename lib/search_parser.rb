# frozen_string_literal: true
# Simplified version of https://github.com/marcelocf/searrrch/blob/f2825e26/lib/searrrch.rb

class SearchParser
  OPERATOR_EXPRESSION = /(\-?\w+):[\ 　]?([\w\p{Han}\p{Katakana}\p{Hiragana}\p{Hangul}ー\.\-,\/]+|(["'])(\\?.)*?\3)/

  attr_accessor :freetext

  def initialize(query)
    query = query.to_s
    @operators = {}

    offset = 0
    while m = OPERATOR_EXPRESSION.match(query, offset)
      key = m[1].downcase.to_sym
      value = m[2]
      value = value[1, value.length - 2] if ["'", '"'].include?(value[0])
      offset = m.end(2)
      @operators[key] ||= []

      value.split(',').each{ |v| @operators[key] << v }
    end
    @freetext = query[offset, query.length].strip
  end

  def [](key)
    @operators[key.to_sym] || []
  end
end
