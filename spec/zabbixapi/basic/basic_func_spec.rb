# Contract: ZabbixApi::Basic - basic_func.rb, the helpers the CRUD is written in terms of
#   classes:  symbolize_keys is a deep copy that accepts a frozen argument | normalize_hash
#             stringifies and drops :hostid | normalize_array recurses | hash_equals? compares
#             normalised and calls a subset equal | skip_update? trusts only the fields the dump
#             carries | compact_params drops nil and emptied sub-objects and keeps false, 0, []
#             and '' | require_field! and require_id! take both key styles and an extra name |
#             one_id! returns the one id, nil for none and refuses more than one distinct id |
#             parse_keys per result shape | merge_params copies and lets the payload win |
#             merge_defaults drops the unset nil placeholders and keeps a caller's own nil |
#             log follows the client's debug option
#   not here: the entry points these helpers serve, which basic_logic_spec.rb asserts;
#             require_field! on Usermacros#update and #update_global, asserted by usermacros_spec.rb
require 'spec_helper'

module BasicFuncSpec
  class Thing < ZabbixApi::Basic
    def method_name
      'thing'
    end

    def identify
      'name'
    end
  end

  # merge_defaults only has work where a class carries default_options, and the four that do all
  # mix nil placeholders with values that must survive - Hosts' interfaces: [] and status: 0,
  # Items' nine empty strings.
  class Defaulted < Thing
    def default_options
      { name: nil, iprange: nil, status: 0, tags: [], note: '', enabled: false }
    end
  end
end

RSpec.describe ZabbixApi::Basic do
  subject(:basic) { BasicFuncSpec::Thing.new(FakeClient.new) }

  def deep_freeze(value)
    case value
    when Hash then value.each_value { |item| deep_freeze(item) }
    when Array then value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end

  describe '#symbolize_keys' do
    nested = { 'a' => 1, 'b' => { 'c' => [{ 'd' => 2 }, 'plain'] } }

    it 'symbolises the keys of nested hashes and of the hashes inside arrays' do
      expect(basic.symbolize_keys(nested)).to eq(a: 1, b: { c: [{ d: 2 }, 'plain'] })
    end

    it 'leaves the argument untouched and copies every level rather than rewriting it' do
      argument = { 'b' => { 'c' => 1 } }
      copy = basic.symbolize_keys(argument)
      expect(argument).to eq('b' => { 'c' => 1 })
      expect(copy.equal?(argument)).to be(false)
      expect(copy[:b].equal?(argument['b'])).to be(false)
    end

    it 'accepts a deep-frozen argument and hands back an unfrozen copy' do
      frozen = deep_freeze('x' => { 'y' => [{ 'z' => 1 }] })
      expect(basic.symbolize_keys(frozen)).to eq(x: { y: [{ z: 1 }] })
      expect(basic.symbolize_keys(frozen).frozen?).to be(false)
    end

    it 'passes a value that is neither Hash nor Array through unchanged' do
      expect([basic.symbolize_keys('text'), basic.symbolize_keys(nil), basic.symbolize_keys(7), basic.symbolize_keys(:sym)]).to eq(['text', nil, 7, :sym])
    end

    it 'is idempotent' do
      expect(basic.symbolize_keys(basic.symbolize_keys(nested))).to eq(a: 1, b: { c: [{ d: 2 }, 'plain'] })
    end
  end

  describe '#normalize_hash' do
    it 'turns every scalar into a String and recurses into arrays' do
      expect(basic.normalize_hash(status: 0, name: 'alpha', tags: [{ tag: 'a', value: 1 }])).to eq(status: '0', name: 'alpha', tags: [{ tag: 'a', value: '1' }])
    end

    it 'drops :hostid' do
      expect(basic.normalize_hash(hostid: 10, name: 'alpha')).to eq(name: 'alpha')
    end

    it 'leaves the caller hash as it was' do
      payload = { hostid: 10, name: 'alpha' }
      basic.normalize_hash(payload)
      expect(payload).to eq(hostid: 10, name: 'alpha')
    end
  end

  describe '#normalize_array' do
    it 'stringifies scalars, recurses into nested arrays and normalises the hashes inside' do
      expect(basic.normalize_array([1, [2, :three], { hostid: 1, value: 4 }])).to eq(['1', %w[2 three], { value: '4' }])
    end
  end

  describe '#hash_equals?' do
    it 'calls 0 and "0" equal' do
      expect(basic.hash_equals?({ status: '0' }, { status: 0 })).to be(true)
    end

    it 'says no as soon as one value differs' do
      expect(basic.hash_equals?({ status: '0' }, { status: 1 })).to be(false)
    end

    it 'calls a payload equal to a dump that merely carries more fields' do
      expect(basic.hash_equals?({ thingid: '42', name: 'alpha', status: '0' }, { name: 'alpha' })).to be(true)
    end
  end

  describe '#skip_update?' do
    dump = { thingid: '42', name: 'alpha', status: '0' }

    it 'skips when every field the payload names is in the dump and matches it' do
      expect(basic.skip_update?(dump, { thingid: 42, name: 'alpha' })).to be(true)
    end

    it 'refuses to skip a field the dump never carried, although the comparison calls the two equal' do
      collection = { thingid: 42, tags: [] }
      expect(basic.hash_equals?(dump, collection)).to be(true)
      expect(basic.skip_update?(dump, collection)).to be(false)
    end

    it 'does not skip when a value differs' do
      expect(basic.skip_update?(dump, { thingid: 42, status: 1 })).to be(false)
    end

    it 'exempts the id itself from the containment test' do
      expect(basic.skip_update?({ name: 'alpha' }, { thingid: 42, name: 'alpha' })).to be(true)
    end
  end

  describe '#compact_params' do
    it 'drops a nil value and a sub-object that emptied out' do
      expect(basic.compact_params(filter: { name: nil }, output: 'extend', limit: nil)).to eq(output: 'extend')
    end

    it 'keeps a sub-object that still holds something' do
      expect(basic.compact_params(filter: { name: 'alpha', hostid: nil }, output: 'extend')).to eq(filter: { name: 'alpha' }, output: 'extend')
    end

    it 'keeps false, 0, an empty Array and an empty String' do
      expect(basic.compact_params(a: false, b: 0, c: [], d: '')).to eq(a: false, b: 0, c: [], d: '')
    end

    it 'leaves the inside of an Array alone' do
      expect(basic.compact_params(rows: [{ name: nil }])).to eq(rows: [{ name: nil }])
    end
  end

  describe '#require_field! and #require_id!' do
    it 'returns the value under a symbol key and under a string key alike' do
      expect([basic.require_field!({ name: 'alpha' }, 'name', 'somewhere'), basic.require_field!({ 'name' => 'alpha' }, 'name', 'somewhere')]).to eq(%w[alpha alpha])
    end

    it 'names the field and the caller when nothing carries a value' do
      expect { basic.require_field!({}, 'host', 'get_ids_by_host') }.to raise_error(ZabbixApi::ApiError, /host not supplied in call to get_ids_by_host/)
    end

    it 'accepts an alternative name, the key itself winning over it' do
      expect(basic.require_id!({ id: 7 }, :id)).to eq(7)
      expect(basic.require_id!({ thingid: 42, id: 7 }, :id)).to eq(42)
    end

    it 'names the key and dump_by_id when an id lookup was given nothing to select on' do
      expect { basic.require_id!(thingid: nil) }.to raise_error(ZabbixApi::ApiError, /thingid not supplied in call to dump_by_id/)
    end
  end

  describe '#one_id!' do
    it 'returns the single id as an Integer, whether the row holds a String or an Integer' do
      expect(basic.one_id!([{ 'thingid' => '42', 'name' => 'alpha' }], 'thingid', 'get_id')).to eq(42)
      expect(basic.one_id!([{ 'thingid' => 42 }], 'thingid', 'get_id')).to eq(42)
    end

    it 'returns nil when it was given no row, and when no row carries the id field' do
      expect([basic.one_id!([], 'thingid', 'get_id'), basic.one_id!([{ 'name' => 'alpha' }], 'thingid', 'get_id')]).to eq([nil, nil])
    end

    it 'refuses more than one distinct id, naming the caller, the object type and every id it found' do
      rows = [{ 'thingid' => '42' }, { 'thingid' => '43' }]
      expect { basic.one_id!(rows, 'thingid', 'get_id') }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 thing objects, not one \(thingid 42, 43\): narrow the lookup\z/)
    end

    it 'counts distinct ids and not rows, so the same object listed twice is still one' do
      expect(basic.one_id!([{ 'thingid' => '42' }, { 'thingid' => '42' }], 'thingid', 'get_id')).to eq(42)
    end

    it 'names whichever caller and id field it was given' do
      rows = [{ 'globalmacroid' => '5' }, { 'globalmacroid' => '6' }]
      expect { basic.one_id!(rows, 'globalmacroid', 'get_id_global') }.to raise_error(ZabbixApi::ApiError, /\Aget_id_global matched 2 thing objects, not one \(globalmacroid 5, 6\)/)
    end

    it 'passes over a row without the id field' do
      rows = [{ 'name' => 'alpha' }, { 'thingid' => '42' }, { 'thingid' => '43' }]
      expect { basic.one_id!(rows, 'thingid', 'get_id') }.to raise_error(ZabbixApi::ApiError, /matched 2 thing objects/)
    end
  end

  describe '#parse_keys' do
    it 'takes the first id out of the result and returns it as an Integer' do
      expect(basic.parse_keys('thingids' => %w[42 43])).to eq(42)
    end

    it 'returns nil for an empty result object' do
      expect(basic.parse_keys({})).to be_nil
    end

    it 'passes a boolean result through' do
      expect([basic.parse_keys(true), basic.parse_keys(false)]).to eq([true, false])
    end

    it 'returns nil for a result that is neither an object nor a boolean' do
      expect(basic.parse_keys(['42'])).to be_nil
    end

    it 'is unguarded against a result object that carries some other key' do
      expect { basic.parse_keys('somethingelse' => ['42']) }.to raise_error(NoMethodError, /undefined method/)
    end
  end

  describe '#merge_params' do
    it 'returns a new hash where the second wins, leaving both arguments as they were' do
      defaults = { name: nil, status: 0 }
      payload = { name: 'alpha' }
      expect(basic.merge_params(defaults, payload)).to eq(name: 'alpha', status: 0)
      expect([defaults, payload]).to eq([{ name: nil, status: 0 }, { name: 'alpha' }])
    end

    it 'merges a normalised string-keyed payload into symbol-keyed defaults on one set of keys' do
      merged = basic.merge_params({ name: nil, status: 0 }, basic.symbolize_keys('name' => 'alpha'))
      expect(merged).to eq(name: 'alpha', status: 0)
      expect(merged.keys).to eq([:name, :status])
    end
  end

  describe '#merge_defaults' do
    subject(:defaulted) { BasicFuncSpec::Defaulted.new(FakeClient.new) }

    it 'drops the nil placeholders the caller left unset and keeps every default that carries a value' do
      expect(defaulted.merge_defaults(name: 'alpha')).to eq(name: 'alpha', status: 0, tags: [], note: '', enabled: false)
    end

    it 'keeps a nil the caller wrote itself' do
      expect(defaulted.merge_defaults(name: 'alpha', iprange: nil)).to include(name: 'alpha', iprange: nil)
    end

    it 'lets the caller win over a default and leaves the caller hash as it was' do
      payload = { name: 'alpha', status: 1 }
      expect(defaulted.merge_defaults(payload)).to include(name: 'alpha', status: 1)
      expect(payload).to eq(name: 'alpha', status: 1)
    end

    it 'keeps a caller nil for a class carrying no defaults' do
      expect(basic.merge_defaults(name: nil)).to eq(name: nil)
    end
  end

  describe '#log' do
    it 'prints the message when the client was built with debug' do
      loud = BasicFuncSpec::Thing.new(FakeClient.new([], debug: true))
      expect { loud.log('[DEBUG] Call create with parameters: {}') }.to output("[DEBUG] Call create with parameters: {}\n").to_stdout
    end

    it 'prints nothing when it was not' do
      expect { basic.log('[DEBUG] Call create with parameters: {}') }.not_to output.to_stdout
    end
  end
end
