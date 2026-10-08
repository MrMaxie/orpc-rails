# frozen_string_literal: true

require "orpc_rails"

# Generated expressions and expected Ruby outcomes; Node independently checks
# them against the exact pinned Zod package. Not RPC wire admission tests.
S = OrpcRails::Schema
cases = [
  [S.string, ["", "😀"], [nil, 1, false]],
  [S.string(min_length: 1, max_length: 1), ["😀", "é"], ["", "e\u0301", "ab"]],
  [S.number, [1, 1.5, -0.0, 9_007_199_254_740_992.0], [nil, "1", true]],
  [S.number(min: -1, max: 2), [-1, 2, 0.5], [-1.1, 2.1]],
  [S.integer, [1.0, -9_007_199_254_740_991, 9_007_199_254_740_991], [1.5, 9_007_199_254_740_992.0]],
  [S.integer(min: 0, max: 2), [0, 2.0], [-1, 3]],
  [S.boolean, [true, false], [0, 1, nil, "true"]],
  [S.literal(nil), [nil], [false, 0, ""]],
  [S.literal(false), [false], [true, nil, 0]],
  [S.literal(1), [1, 1.0], [true, "1", 2]],
  [S.literal("x\"\\ é"), ["x\"\\ é"], ["x", nil]],
  [S.enum("blue", "é"), ["blue", "é"], ["red", nil, 1]],
  [S.array(S.string, min_length: 1, max_length: 2), [["one"], ["one", "two"]], [[], [1], ["1", "2", "3"]]],
  [S.object(name: S.string, note: S.string.nullable, extra: S.integer.optional),
    [{ "name" => "blue", "note" => nil }, { "name" => "blue", "note" => "x", "extra" => 1.0 }],
    [{ "name" => "blue" }, { "name" => "blue", "note" => nil, "extra" => nil },
      { "name" => "blue", "note" => nil, "unknown" => 1 }]],
  [S.object(value: S.string.nullable.optional), [{}, { "value" => nil }, { "value" => "x" }], [{ "value" => 1 }]],
  [S.object(nested: S.array(S.object(id: S.integer))), [{ "nested" => [{ "id" => 1 }] }],
    [{ "nested" => [{ "id" => 1, "extra" => 2 }] }, { "nested" => [nil] }]],
  [S.number.nullable, [nil, 1.5], ["1", false]]
]

lines = cases.each_with_index.map do |(schema, valid, invalid), index|
  samples = [[true, valid], [false, invalid]].flat_map do |expected, values|
    values.map do |value|
      actual = OrpcRails::Validator.valid?(schema, value)
      raise "Ruby conformance case #{index} failed" unless actual == expected
      { value: value, expected: expected }
    end
  end
  "  { schema: #{schema.to_zod}, samples: #{JSON.generate(samples, ascii_only: true)} }"
end
puts 'import * as z from "zod"'
puts "export const conformance = [\n#{lines.join(",\n")}\n]"
