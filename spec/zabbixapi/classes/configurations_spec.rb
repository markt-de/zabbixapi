require 'spec_helper'

describe 'ZabbixApi::Configurations' do
  let(:configurations_mock) { ZabbixApi::Configurations.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { configurations_mock.method_name }

    it { is_expected.to eq 'configuration' }
  end

  # There is no configuration object in the API, so there is no natural key to identify one
  # by; only export/import are supported.
  describe '.identify' do
    it 'raises, because the configuration API has no object to identify' do
      expect { configurations_mock.identify }.to raise_error(ZabbixApi::ApiError)
    end
  end

  describe '.export' do
    subject { configurations_mock.export(data) }

    let(:data) { { testdata: 222 } }
    let(:result) { { test: 1 } }

    before do
      allow(client).to receive(:api_request).with(
        method: 'configuration.export',
        params: data
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.import' do
    subject { configurations_mock.import(data) }

    let(:data) { { testdata: 222 } }
    let(:result) { { test: 1 } }

    before do
      allow(client).to receive(:api_request).with(
        method: 'configuration.import',
        params: data
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end
end
