require 'spec_helper'

describe 'ZabbixApi::Problems' do
  let(:problems_mock) { ZabbixApi::Problems.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { problems_mock.method_name }

    it { is_expected.to eq 'problem' }
  end

  describe '.identify' do
    subject { problems_mock.identify }

    it { is_expected.to eq 'name' }
  end

  # Problems are identified by the id of the event that created them; the API has no
  # problemid property.
  describe '.key' do
    subject { problems_mock.key }

    it { is_expected.to eq 'eventid' }
  end

  describe '.keys' do
    subject { problems_mock.keys }

    it { is_expected.to eq 'eventids' }
  end

  # problem.get is the only method the API provides.
  describe 'unsupported write operations' do
    [:create, :delete, :update, :create_or_update, :get_or_create].each do |unsupported|
      it "raises on ##{unsupported}" do
        expect { problems_mock.public_send(unsupported, {}) }
          .to raise_error(ZabbixApi::ApiError, /only provides problem\.get/)
      end
    end
  end
end
