# Contract: ZabbixApi::Basic - basic_alias.rb, the three friendly aliases
#   classes:  get, add and destroy produce the traffic of get_full_data, create and delete | they
#             call rather than alias, so a subclass overriding the target is followed | they return
#             what the target returned | Basic's own method_name comes from basic_init.rb and raises
#   not here: the wire shape of the three targets, which basic_logic_spec.rb asserts; add and
#             destroy on Events and Problems, which refuse there because create and delete do, as
#             those classes' specs assert
require 'spec_helper'

module BasicAliasSpec
  class Thing < ZabbixApi::Basic
    def method_name
      'thing'
    end

    def identify
      'name'
    end
  end

  # Problems rewrites get_full_data entirely and Graphs turns it into a substring search; the alias
  # has to follow such an override, which it does only because it calls the method by name.
  class Overriding < Thing
    def get_full_data(data)
      ['overridden', data]
    end
  end
end

RSpec.describe ZabbixApi::Basic do
  row = { 'thingid' => '42', 'name' => 'alpha' }
  read = { method: 'thing.get', params: {}, result: [row] }
  created = { method: 'thing.create', params: {}, result: { 'thingids' => ['42'] } }
  deleted = { method: 'thing.delete', params: {}, result: { 'thingids' => ['42'] } }

  describe BasicAliasSpec::Thing do
    it_behaves_like 'the aliases', exchanges: [read, created, deleted], payload: { name: 'alpha' }, id: 42

    it 'returns what the target returned: the rows, the new id, the deleted id' do
      client = FakeClient.new([read, created, deleted])
      thing = described_class.new(client)
      expect(thing.get(name: 'alpha')).to eq([row])
      expect(thing.add(name: 'alpha')).to eq(42)
      expect(thing.destroy(42)).to eq(42)
    end
  end

  describe BasicAliasSpec::Overriding do
    it 'get follows a subclass that overrides get_full_data' do
      expect(described_class.new(FakeClient.new).get(name: 'alpha')).to eq(['overridden', { name: 'alpha' }])
    end
  end

  describe 'method_name on Basic itself' do
    it 'comes from basic_init.rb and raises' do
      expect(described_class.instance_method(:method_name).source_location.first).to end_with('basic_init.rb')
      expect { described_class.new(FakeClient.new).method_name }.to raise_error(ZabbixApi::ApiError, /Can't call method_name here/)
    end
  end
end
