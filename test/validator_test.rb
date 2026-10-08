# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/orpc_rails/schema"
require_relative "../lib/orpc_rails/validator"

class ValidatorTest < Minitest::Test
  S = OrpcRails::Schema
  V = OrpcRails::Validator

  def test_strict_object_omission_null_and_no_coercion
    schema = S.object(name: S.string, note: S.string.nullable, extra: S.integer.optional)
    value = { "name" => "blue", "note" => nil }
    assert V.valid?(schema, value)
    assert_equal({ "name" => "blue", "note" => nil }, value)
    [ { "name" => "blue" }, value.merge("extra" => nil), value.merge("other" => 1),
      { name: "blue", note: nil }, value.merge("name" => 42) ].each { |bad| refute V.valid?(schema, bad) }
  end

  def test_all_primitive_nodes_and_wrappers
    assert V.valid?(S.boolean, true)
    refute V.valid?(S.boolean, 1)
    assert V.valid?(S.literal(nil), nil)
    assert V.valid?(S.literal(1), 1.0)
    refute V.valid?(S.literal(1), true)
    assert V.valid?(S.literal(false), false)
    refute V.valid?(S.literal(false), nil)
    assert V.valid?(S.enum("blue", "red"), "blue")
    refute V.valid?(S.enum("blue", "red"), :blue)
    assert V.valid?(S.number.nullable, nil)
    refute V.valid?(S.number, "1")
  end

  def test_boolean_does_not_call_equality_hooks_on_arbitrary_output
    value = Object.new
    def value.==(_) = true
    refute V.valid?(S.boolean, value)
    def value.==(_) = raise("equality hook must not run")
    refute V.valid?(S.boolean, value)
  end

  def test_finite_number_bounds_and_safe_integer_float_semantics
    assert V.valid?(S.number, 9_007_199_254_740_992.0) # Wire policy is independent.
    refute V.valid?(S.number, Float::INFINITY)
    refute V.valid?(S.number, Float::NAN)
    assert V.valid?(S.number(min: -1, max: 1), 1.0)
    refute V.valid?(S.number(min: -1, max: 1), 1.01)
    assert V.valid?(S.integer, 1.0)
    refute V.valid?(S.integer, 1.5)
    refute V.valid?(S.integer, 9_007_199_254_740_992.0)
    refute V.valid?(S.integer(min: 0, max: 2), -1)
  end

  def test_unicode_codepoints_and_lengths
    schema = S.string(min_length: 1, max_length: 1)
    ["😀", "é"].each { |value| assert V.valid?(schema, value) }
    ["", "e\u0301", "\xFF".b].each { |value| refute V.valid?(schema, value) }
    array = S.array(S.string, min_length: 1, max_length: 2)
    assert V.valid?(array, ["one", "two"])
    [[], [1], ["1", "2", "3"]].each { |value| refute V.valid?(array, value) }
  end
end
