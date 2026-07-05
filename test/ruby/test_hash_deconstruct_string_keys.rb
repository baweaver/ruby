# frozen_string_literal: true

require "test/unit"
require "json"

# Tests for Hash#deconstruct_keys String-key resolution.
# This feature allows pattern matching to transparently resolve
# Symbol pattern keys against String hash keys.
class TestHashDeconstructKeysStringResolution < Test::Unit::TestCase
  # === Fast path: Symbol-keyed hashes are unchanged ===

  def test_symbol_keyed_hash_returns_self
    h = { a: 1, b: 2, c: 3 }
    result = h.deconstruct_keys([:a, :b])
    assert_same h, result, "Symbol-keyed hash should return self"
  end

  def test_symbol_keyed_hash_pattern_matches
    h = { a: 1, b: 2, c: 3 }
    result = case h
             in { a: Integer, b: Integer }
               true
             else
               false
             end
    assert_equal true, result
  end

  def test_nil_keys_returns_self
    h = { "name" => "Alice" }
    assert_same h, h.deconstruct_keys(nil)
  end

  # === String-key resolution ===

  def test_string_keyed_hash_resolves_symbol_keys
    h = { "name" => "Alice", "age" => 30 }
    result = h.deconstruct_keys([:name, :age])
    assert_equal "Alice", result[:name]
    assert_equal 30, result[:age]
  end

  def test_string_keyed_hash_pattern_matches
    h = { "name" => "Alice", "role" => "admin" }
    matched = case h
              in { name: String => name, role: "admin" }
                name
              else
                nil
              end
    assert_equal "Alice", matched
  end

  def test_nested_string_keyed_hash_pattern_matches
    h = { "status" => 200, "body" => { "id" => 42, "type" => "user" } }
    matched = case h
              in { status: 200, body: { id: Integer => id, type: "user" } }
                id
              else
                nil
              end
    assert_equal 42, matched
  end

  def test_parsed_json_pattern_matches
    json = JSON.parse('{"name": "Alice", "active": true}')
    matched = case json
              in { name: String => name, active: true }
                name
              else
                nil
              end
    assert_equal "Alice", matched
  end

  # === Mixed hashes ===

  def test_mixed_hash_resolves_both_key_types
    h = { a: 1, "b" => 2, c: 3 }
    result = h.deconstruct_keys([:a, :b, :c])
    assert_equal 1, result[:a]
    assert_equal 2, result[:b]
    assert_equal 3, result[:c]
  end

  def test_mixed_hash_pattern_matches
    h = { a: 1, "b" => 2, c: 3 }
    result = case h
             in { a: Integer, b: Integer, c: Integer }
               true
             else
               false
             end
    assert_equal true, result
  end

  # === Safety: Hash#[] and other methods unchanged ===

  def test_bracket_does_not_resolve
    h = { "name" => "Alice" }
    assert_nil h[:name]
  end

  def test_key_question_does_not_resolve
    h = { "name" => "Alice" }
    assert_equal false, h.key?(:name)
  end

  def test_fetch_does_not_resolve
    h = { "name" => "Alice" }
    assert_raise(KeyError) { h.fetch(:name) }
  end

  def test_dig_does_not_resolve
    h = { "name" => "Alice" }
    assert_nil h.dig(:name)
  end

  # === Edge cases ===

  def test_missing_key_not_included_in_result
    h = { "name" => "Alice" }
    result = h.deconstruct_keys([:name, :missing])
    assert_equal "Alice", result[:name]
    assert_equal false, result.key?(:missing)
  end

  def test_no_string_fallback_returns_self_for_error_messages
    h = { a: 1 }
    result = h.deconstruct_keys([:nonexistent])
    assert_same h, result
  end

  def test_integer_keys_unaffected
    h = { 1 => "one", 2 => "two" }
    result = case h
             in { a: String }
               true
             else
               false
             end
    assert_equal false, result
  end

  def test_empty_hash
    h = {}
    result = h.deconstruct_keys([:a])
    assert_same h, result
  end

  def test_symbol_key_takes_precedence_over_string
    h = { a: "symbol_value", "a" => "string_value" }
    result = h.deconstruct_keys([:a])
    assert_equal "symbol_value", result[:a]
  end

  # === Pattern matching with captures ===

  def test_capture_from_string_keyed_hash
    h = { "name" => "Alice", "scores" => [95, 88, 72] }
    case h
    in { name: String => name, scores: [Integer => first, *] }
      assert_equal "Alice", name
      assert_equal 95, first
    else
      flunk "Pattern should have matched"
    end
  end

  def test_guard_clause_with_string_keys
    h = { "age" => 25 }
    matched = case h
              in { age: (18..) => age }
                age
              else
                nil
              end
    assert_equal 25, matched
  end

  # === **rest patterns (known limitation) ===

  def test_rest_pattern_does_not_resolve_string_keys
    # **rest causes the VM to pass nil for keys, which returns self.
    # The VM then drives key?/delete on self, and key?(:name) fails
    # on a string-keyed hash. This is a known limitation.
    h = { "name" => "Alice", "age" => 30 }
    matched = case h
              in { name: String => name, **rest }
                name
              else
                nil
              end
    assert_nil matched, "**rest patterns do not support string-key resolution (known limitation)"
  end

  # === Flag propagation ===

  def test_replace_propagates_flag
    h = { a: 1 }
    h.replace({ "name" => "Alice" })
    result = h.deconstruct_keys([:name])
    assert_equal "Alice", result[:name]
  end

  def test_replace_clears_flag
    h = { "a" => 1 }
    h.replace({ b: 2 })
    result = h.deconstruct_keys([:b])
    assert_same h, result
  end

  def test_dup_preserves_flag
    original = { "name" => "Alice" }
    duped = original.dup
    result = duped.deconstruct_keys([:name])
    assert_equal "Alice", result[:name]
  end

  # === compare_by_identity ===

  def test_compare_by_identity_does_not_set_flag
    h = {}.compare_by_identity
    h["name"] = "Alice"
    # RHASH_STRING_KEY_P excludes identity hashes, so the flag is never set.
    # deconstruct_keys returns self, and the VM's key?(:name) fails.
    matched = case h
              in { name: String }
                true
              else
                false
              end
    assert_equal false, matched
  end

  # === Partial resolution and error messages ===

  def test_partial_resolution_returns_resolved_hash_not_self
    h = { "name" => "Alice" }
    # :name resolves, :missing does not.
    result = h.deconstruct_keys([:name, :missing])
    assert_equal "Alice", result[:name]
    assert_equal false, result.key?(:missing)
    # The result is NOT self because string fallback did help for :name
    refute_same h, result
  end

  # === Invariant: any operation yielding a hash with a String key
  #     must preserve the flag so pattern matching works. ===

  def test_merge_preserves_flag
    h = {}; h["name"] = "Alice"
    merged = h.merge({})
    assert_pattern_matches merged, :name, "Alice"
  end

  def test_select_preserves_flag
    h = {}; h["name"] = "Alice"; h["age"] = 30
    selected = h.select { |_, v| v.is_a?(String) }
    assert_pattern_matches selected, :name, "Alice"
  end

  def test_reject_preserves_flag
    h = {}; h["name"] = "Alice"; h["junk"] = nil
    rejected = h.reject { |_, v| v.nil? }
    assert_pattern_matches rejected, :name, "Alice"
  end

  def test_transform_values_preserves_flag
    h = {}; h["name"] = "alice"
    transformed = h.transform_values(&:upcase)
    assert_pattern_matches transformed, :name, "ALICE"
  end

  def test_compact_preserves_flag
    h = {}; h["a"] = 1; h["b"] = nil
    compacted = h.compact
    assert_pattern_matches compacted, :a, 1
  end

  def test_to_h_block_preserves_flag
    h = {}; h["name"] = "Alice"
    converted = h.to_h { |key, val| [key, val] }
    assert_pattern_matches converted, :name, "Alice"
  end

  private

  def assert_pattern_matches(hash, sym_key, expected_value)
    result = hash.deconstruct_keys([sym_key])
    assert_equal expected_value, result[sym_key],
      "Expected #{hash.inspect}.deconstruct_keys([#{sym_key.inspect}]) to resolve, got #{result.inspect}"
  end

  # === Array of hashes (common JSON pattern) ===

  def test_select_from_array_of_string_keyed_hashes
    users = [
      { "name" => "Alice", "role" => "admin" },
      { "name" => "Bob", "role" => "viewer" },
      { "name" => "Carol", "role" => "admin" }
    ]
    admins = users.select { |u| u in { role: "admin" } }
    assert_equal 2, admins.size
    assert_equal "Alice", admins[0]["name"]
    assert_equal "Carol", admins[1]["name"]
  end

end
