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

  # The event API provides only event.get and event.acknowledge.
  describe 'unsupported write operations' do
    [:create, :delete, :update, :create_or_update, :get_or_create].each do |unsupported|
      it "raises on ##{unsupported}" do
        expect { events_mock.public_send(unsupported, {}) }
          .to raise_error(ZabbixApi::ApiError, /only provides event\.get/)
      end
    end
  end
end
