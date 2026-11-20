# Contract: ZabbixApi::Basic - basic_init.rb, the constructor and the hooks
#   classes:  the abstract hooks refuse rather than guess | a concrete subclass names its object
#             and its identify field | key derives from method_name, keys from key | an overridden
#             key carries into the plural | default_options is empty until a subclass carries one |
#             the constructor keeps the client its requests go to
#   not here: what those hooks are on each resource class, which that class's own spec asserts;
#             Configurations, whose identify is unset, and the five methods that then raise locally
require 'spec_helper'

# Basic is abstract, so apart from its own hooks it is driven through concrete subclasses: Thing is
# the minimal one a resource class is, two hooks and the rest inherited.
module BasicInitSpec
  class Thing < ZabbixApi::Basic
    def method_name
      'thing'
    end

    def identify
      'name'
    end
  end

  # Where the API's id property is not <object>id, a class overrides key alone and lets Basic build
  # the plural from it: HostGroups groupid, Proxygroup proxy_groupid, Usergroups usrgrpid,
  # Usermacros hostmacroid, Problems eventid, TemplateGroups groupid.
  class Keyed < Thing
    def key
      'thing_id'
    end
  end

  # The four classes that merge defaults into a create (Items, Hosts, HttpTests, Drules) override
  # this hook; a nil placeholder is theirs too and is dropped by merge_defaults instead of going out
  # as JSON null.
  class Defaulted < Thing
    def default_options
      { name: nil, status: 0, tags: [] }
    end
  end
end

RSpec.describe ZabbixApi::Basic do
  describe 'the abstract hooks' do
    subject(:basic) { described_class.new(FakeClient.new) }

    it 'refuses method_name' do
      expect { basic.method_name }.to raise_error(ZabbixApi::ApiError, /Can't call method_name here/)
    end

    it 'refuses identify' do
      expect { basic.identify }.to raise_error(ZabbixApi::ApiError, /Can't call identify here/)
    end

    it "refuses key and keys with method_name's refusal" do
      expect { basic.key }.to raise_error(ZabbixApi::ApiError, /Can't call method_name here/)
      expect { basic.keys }.to raise_error(ZabbixApi::ApiError, /Can't call method_name here/)
    end

    # Four classes override this hook; the other nineteen live with the empty default.
    it 'answers default_options with an empty hash' do
      expect(basic.default_options).to eq({})
    end
  end

  describe BasicInitSpec::Thing do
    it_behaves_like 'a Basic resource', method_name: 'thing', identify: 'name', key: 'thingid', keys: 'thingids', default_options: {}

    it 'sends its requests to the client it was constructed with' do
      client = FakeClient.new([{ method: 'thing.get', params: {}, result: [] }])
      described_class.new(client).all
      expect(client.count('thing.get')).to eq(1)
    end
  end

  describe BasicInitSpec::Keyed do
    it_behaves_like 'a Basic resource', method_name: 'thing', identify: 'name', key: 'thing_id', keys: 'thing_ids', default_options: {}
  end

  describe BasicInitSpec::Defaulted do
    it_behaves_like 'a Basic resource', method_name: 'thing', identify: 'name', key: 'thingid', keys: 'thingids', default_options: { name: nil, status: 0, tags: [] }
  end
end
