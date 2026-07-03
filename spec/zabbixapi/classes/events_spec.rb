require 'spec_helper'

describe 'ZabbixApi::Events' do
  let(:events_mock) { ZabbixApi::Events.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { events_mock.method_name }

    it { is_expected.to eq 'event' }
  end

  describe '.identify' do
    subject { events_mock.identify }

    it { is_expected.to eq 'name' }
  end
end
