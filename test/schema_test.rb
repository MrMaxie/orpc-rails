# frozen_string_literal: true

require "minitest/autorun"
require "orpc_rails/schema"

class SchemaTest < Minitest::Test
  S = OrpcRails::Schema
  Node = OrpcRails::Schema::Node
  SAFE_MAX = 9_007_199_254_740_991
  SAFE_MIN = -9_007_199_254_740_991

  # --- node shapes -------------------------------------------------------

  def test_string_node_shape
    node = S.string
    assert_equal :string, node.kind
    assert_equal({ min_length: nil, max_length: nil }, node.options)
    assert_nil node.children
    assert_predicate node, :frozen?
    assert_predicate node.options, :frozen?
  end

  def test_string_bounds_are_recorded
    assert_equal({ min_length: 2, max_length: 5 },
                 S.string(min_length: 2, max_length: 5).options)
  end

  def test_string_rejects_invalid_bounds
    assert_raises(ArgumentError) { S.string(min_length: -1) }
    assert_raises(ArgumentError) { S.string(max_length: -1) }
    assert_raises(ArgumentError) { S.string(min_length: 1.5) }
    assert_raises(ArgumentError) { S.string(min_length: "2") }
    assert_raises(ArgumentError) { S.string(min_length: 3, max_length: 2) }
  end

  def test_number_node_shape
    node = S.number(min: 0, max: 1.5)
    assert_equal :number, node.kind
    assert_equal({ min: 0, max: 1.5 }, node.options)
    assert_nil node.children
  end

  def test_number_rejects_invalid_bounds
    assert_raises(ArgumentError) { S.number(min: Float::NAN) }
    assert_raises(ArgumentError) { S.number(max: Float::INFINITY) }
    assert_raises(ArgumentError) { S.number(min: -Float::INFINITY) }
    assert_raises(ArgumentError) { S.number(min: 2, max: 1) }
    assert_raises(ArgumentError) { S.number(min: "0") }
    assert_raises(ArgumentError) { S.number(min: 0..1) }
  end

  def test_numeric_and_length_bounds_cannot_round_or_overflow_in_javascript
    assert_raises(ArgumentError) { S.number(max: SAFE_MAX + 2) }
    assert_raises(ArgumentError) { S.number(min: -(10**400)) }
    assert_raises(ArgumentError) { S.string(max_length: SAFE_MAX + 2) }
    assert_raises(ArgumentError) { S.array(S.string, min_length: SAFE_MAX + 2) }
  end

  def test_integer_defaults_to_safe_integer_range
    assert_equal({ min: SAFE_MIN, max: SAFE_MAX }, S.integer.options)
  end

  def test_integer_accepts_explicit_safe_bounds
    assert_equal({ min: 0, max: 100 }, S.integer(min: 0, max: 100).options)
  end

  def test_integer_rejects_bounds_outside_safe_range
    assert_raises(ArgumentError) { S.integer(min: SAFE_MIN - 1) }
    assert_raises(ArgumentError) { S.integer(max: SAFE_MAX + 1) }
  end

  def test_integer_rejects_invalid_bounds
    assert_raises(ArgumentError) { S.integer(min: 1.5) }
    assert_raises(ArgumentError) { S.integer(min: 5, max: 4) }
    assert_raises(ArgumentError) { S.integer(min: "1") }
  end

  def test_boolean_node_shape
    node = S.boolean
    assert_equal :boolean, node.kind
    assert_equal({}, node.options)
    assert_nil node.children
  end

  def test_literal_accepts_json_scalars
    assert_equal "x", S.literal("x").options[:value]
    assert_equal 2, S.literal(2).options[:value]
    assert_equal 1.5, S.literal(1.5).options[:value]
    assert_equal true, S.literal(true).options[:value]
    assert_equal false, S.literal(false).options[:value]
    assert_nil S.literal(nil).options[:value]
    assert_equal :literal, S.literal(nil).kind
  end

  def test_literal_rejects_unsafe_integers
    assert_raises(ArgumentError) { S.literal(2**53) }
    assert_raises(ArgumentError) { S.literal(-(2**53)) }
  end

  def test_literal_rejects_nonfinite_floats
    assert_raises(ArgumentError) { S.literal(Float::NAN) }
    assert_raises(ArgumentError) { S.literal(Float::INFINITY) }
    assert_raises(ArgumentError) { S.literal(-Float::INFINITY) }
  end

  def test_literal_rejects_unsupported_values
    assert_raises(ArgumentError) { S.literal(:sym) }
    assert_raises(ArgumentError) { S.literal([1]) }
    assert_raises(ArgumentError) { S.literal({}) }
    assert_raises(ArgumentError) { S.literal(Object.new) }
  end

  def test_enum_node_shape
    node = S.enum("a", "b")
    assert_equal :enum, node.kind
    assert_equal ["a", "b"], node.options[:values]
    assert_nil node.children
  end

  def test_enum_rejects_invalid_values
    assert_raises(ArgumentError) { S.enum }
    assert_raises(ArgumentError) { S.enum("a", 1) }
    assert_raises(ArgumentError) { S.enum(:a) }
    assert_raises(ArgumentError) { S.enum("a", "a") }
  end

  def test_array_node_shape
    inner = S.string
    node = S.array(inner, min_length: 1, max_length: 3)
    assert_equal :array, node.kind
    assert_equal({ min_length: 1, max_length: 3 }, node.options)
    assert_same inner, node.children
  end

  def test_array_rejects_non_node_elements
    assert_raises(ArgumentError) { S.array("x") }
    assert_raises(ArgumentError) { S.array(nil) }
    assert_raises(ArgumentError) { S.array(:string) }
  end

  def test_array_rejects_optional_elements
    assert_raises(ArgumentError) { S.array(S.string.optional) }
  end

  def test_array_rejects_invalid_bounds
    assert_raises(ArgumentError) { S.array(S.string, min_length: -1) }
    assert_raises(ArgumentError) { S.array(S.string, min_length: 2, max_length: 1) }
    assert_raises(ArgumentError) { S.array(S.string, min_length: 0.5) }
  end

  def test_object_children_are_sorted_frozen_string_key_hash
    node = S.object(b: S.string, a: S.number, c: S.boolean)
    assert_equal :object, node.kind
    assert_equal({}, node.options)
    assert_equal %w[a b c], node.children.keys
    assert_predicate node.children, :frozen?
    node.children.each_key do |key|
      assert_instance_of String, key
      assert_predicate key, :frozen?
    end
    assert_equal :number, node.children["a"].kind
    assert_equal :string, node.children["b"].kind
    assert_equal :boolean, node.children["c"].kind
  end

  def test_object_accepts_string_keys
    node = S.object(**{ "a" => S.string })
    assert_equal ["a"], node.children.keys
  end

  def test_object_key_order_does_not_change_output
    assert_equal S.object(a: S.string, b: S.number).to_zod,
                 S.object(b: S.number, a: S.string).to_zod
  end

  def test_object_rejects_unsafe_property_keys
    assert_raises(ArgumentError) { S.object(__proto__: S.string) }
    assert_raises(ArgumentError) { S.object(constructor: S.string) }
    assert_raises(ArgumentError) { S.object(prototype: S.string) }
    assert_raises(ArgumentError) { S.object(**{ "__proto__" => S.string }) }
    assert_raises(ArgumentError) { S.object(**{ "constructor" => S.string }) }
    assert_raises(ArgumentError) { S.object(**{ "prototype" => S.string }) }
  end

  def test_object_rejects_unknown_property_nodes
    assert_raises(ArgumentError) { S.object(name: "x") }
    assert_raises(ArgumentError) { S.object(name: nil) }
    assert_raises(ArgumentError) { S.object(name: :string) }
  end

  def test_object_rejects_duplicate_keys_after_stringification
    assert_raises(ArgumentError) do
      S.object(a: S.string, **{ "a" => S.number })
    end
  end

  def test_object_allows_optional_properties
    node = S.object(nickname: S.string.optional)
    assert_equal :optional, node.children["nickname"].kind
  end

  def test_optional_and_nullable_wrappers
    inner = S.string
    opt = inner.optional
    assert_equal :optional, opt.kind
    assert_same inner, opt.children
    assert_equal({}, opt.options)
    nul = inner.nullable
    assert_equal :nullable, nul.kind
    assert_same inner, nul.children
    assert_equal({}, nul.options)
    assert_predicate opt, :frozen?
    assert_predicate nul, :frozen?
  end

  def test_optional_cannot_wrap_optional_or_be_wrapped_by_nullable
    assert_raises(ArgumentError) { S.string.optional.optional }
    assert_raises(ArgumentError) { S.string.optional.nullable }
    assert_raises(ArgumentError) { S.array(S.string.nullable.optional) }
  end

  def test_node_rejects_unsupported_kind
    assert_raises(ArgumentError) { Node.new(:regex, {}, nil) }
    assert_raises(ArgumentError) { Node.new("string", {}, nil) }
    assert_raises(ArgumentError) { Node.new(nil, {}, nil) }
  end

  def test_node_rejects_unsupported_options
    assert_raises(ArgumentError) { Node.new(:string, { bogus: 1 }, nil) }
    assert_raises(ArgumentError) { Node.new(:object, { min: 1 }, {}) }
  end

  def test_node_rejects_mismatched_children
    assert_raises(ArgumentError) { Node.new(:string, {}, "x") }
    assert_raises(ArgumentError) { Node.new(:object, {}, nil) }
    assert_raises(ArgumentError) { Node.new(:array, {}, {}) }
    assert_raises(ArgumentError) { Node.new(:optional, {}, nil) }
    assert_raises(ArgumentError) { Node.new(:nullable, {}, {}) }
  end

  def test_node_fills_integer_bounds_when_omitted
    assert_equal({ min: SAFE_MIN, max: SAFE_MAX }, Node.new(:integer, {}, nil).options)
  end

  # --- to_zod ------------------------------------------------------------

  def test_to_zod_string
    assert_equal "z.string()", S.string.to_zod
    assert_equal "z.string().min(2)", S.string(min_length: 2).to_zod
    assert_equal "z.string().max(5)", S.string(max_length: 5).to_zod
    assert_equal "z.string().min(2).max(5)", S.string(min_length: 2, max_length: 5).to_zod
    assert_equal "z.string().min(0)", S.string(min_length: 0).to_zod
  end

  def test_to_zod_number
    assert_equal "z.number()", S.number.to_zod
    assert_equal "z.number().min(0)", S.number(min: 0).to_zod
    assert_equal "z.number().max(1.5)", S.number(max: 1.5).to_zod
    assert_equal "z.number().min(-1).max(1)", S.number(min: -1, max: 1).to_zod
  end

  def test_to_zod_integer
    assert_equal "z.int()", S.integer.to_zod
    assert_equal "z.int()", S.integer(min: SAFE_MIN, max: SAFE_MAX).to_zod
    assert_equal "z.int().min(0)", S.integer(min: 0).to_zod
    assert_equal "z.int().min(0).max(100)", S.integer(min: 0, max: 100).to_zod
  end

  def test_to_zod_boolean
    assert_equal "z.boolean()", S.boolean.to_zod
  end

  def test_to_zod_literal
    assert_equal "z.literal(2)", S.literal(2).to_zod
    assert_equal "z.literal(1.0)", S.literal(1.0).to_zod
    assert_equal "z.literal(-1.5)", S.literal(-1.5).to_zod
    assert_equal "z.literal(true)", S.literal(true).to_zod
    assert_equal "z.literal(false)", S.literal(false).to_zod
    assert_equal "z.literal(null)", S.literal(nil).to_zod
    assert_equal 'z.literal("hi")', S.literal("hi").to_zod
  end

  def test_to_zod_escapes_literal_content
    assert_equal 'z.literal("a\\"b\\\\c\\u00e9")', S.literal("a\"b\\c\u00e9").to_zod
    assert_equal 'z.literal("\u2028")', S.literal("\u2028").to_zod
    assert_equal 'z.literal("\u00e9")', S.literal("\u00e9").to_zod
  end

  def test_to_zod_literal_cannot_inject_typescript
    assert_equal 'z.enum(["x\\");evil();(\\""])', S.enum('x");evil();("').to_zod
  end

  def test_to_zod_enum
    assert_equal 'z.enum(["a"])', S.enum("a").to_zod
    assert_equal 'z.enum(["a", "b"])', S.enum("a", "b").to_zod
    assert_equal 'z.enum(["b", "a"])', S.enum("b", "a").to_zod
  end

  def test_to_zod_array
    assert_equal "z.array(z.string())", S.array(S.string).to_zod
    assert_equal "z.array(z.string()).min(1).max(3)",
                 S.array(S.string, min_length: 1, max_length: 3).to_zod
    assert_equal "z.array(z.array(z.number()))", S.array(S.array(S.number)).to_zod
  end

  def test_to_zod_object
    assert_equal "z.strictObject({})", S.object.to_zod
    assert_equal 'z.strictObject({"a": z.string(), "b": z.int()})',
                 S.object(a: S.string, b: S.integer).to_zod
    assert_equal 'z.strictObject({"a\\"b": z.string()})',
                 S.object(**{ 'a"b' => S.string }).to_zod
  end

  def test_to_zod_object_property_modifiers
    assert_equal 'z.strictObject({"nickname": z.string().optional(), "note": z.string().nullable()})',
                 S.object(nickname: S.string.optional, note: S.string.nullable).to_zod
    assert_equal 'z.strictObject({"n": z.string().nullable().optional()})',
                 S.object(n: S.string.nullable.optional).to_zod
  end

  def test_to_zod_nested
    node = S.object(items: S.array(S.object(id: S.string)), count: S.integer(min: 0))
    assert_equal 'z.strictObject({"count": z.int().min(0), "items": z.array(z.strictObject({"id": z.string()}))})',
                 node.to_zod
  end

  def test_to_zod_rejects_root_optional
    assert_raises(ArgumentError) { S.string.optional.to_zod }
    assert_raises(ArgumentError) { S.string.nullable.optional.to_zod }
    assert_raises(ArgumentError) { S.array(S.string).optional.to_zod }
  end

  # --- immutability ------------------------------------------------------

  def test_nodes_copy_caller_strings
    value = String.new("x")
    enum_value = String.new("e")
    key = String.new("k")
    lit = S.literal(value)
    enum_node = S.enum(enum_value)
    obj = S.object(**{ key => S.string })
    value << "y"
    enum_value << "y"
    key << "y"
    assert_equal 'z.literal("x")', lit.to_zod
    assert_equal 'z.enum(["e"])', enum_node.to_zod
    assert_equal 'z.strictObject({"k": z.string()})', obj.to_zod
  end

  def test_copied_strings_are_frozen
    assert_predicate S.literal("x").options[:value], :frozen?
    assert_predicate S.enum("a").options[:values].first, :frozen?
    assert_predicate S.enum("a").options[:values], :frozen?
    S.object(**{ "k" => S.string }).children.each_key { |k| assert_predicate k, :frozen? }
  end
end
