require 'spec_helper'

describe 'ZabbixApi::Proxies' do
  let(:proxies_mock) { ZabbixApi::Proxies.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { proxies_mock.method_name }

    it { is_expected.to eq 'proxy' }
  end

  describe '.identify' do
    subject { proxies_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.delete' do
    subject { proxies_mock.delete(data) }

    let(:data) { ['222'] }
    let(:result) { { 'proxyids' => ['1'] } }

    before do
      allow(proxies_mock).to receive(:log)
      allow(client).to receive(:api_request).with(
        method: 'proxy.delete',
        params: data
      ).and_return(result)
    end

    context 'when result is not empty' do
      it 'returns the id of the first proxy' do
        expect(subject).to eq 1
      end
    end

    context 'when result is empty' do
      let(:result) { [] }

      it { is_expected.to be_nil }
    end
  end
end
