require 'spec_helper'

describe 'ZabbixApi::Proxygroup' do
  let(:proxygroup_mock) { ZabbixApi::Proxygroup.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { proxygroup_mock.method_name }

    it { is_expected.to eq 'proxygroup' }
  end

  describe '.identify' do
    subject { proxygroup_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.key' do
    subject { proxygroup_mock.key }

    it { is_expected.to eq 'proxy_groupid' }
  end

  describe '.delete' do
    subject { proxygroup_mock.delete(data) }

    let(:data) { ['222'] }
    let(:result) { { 'proxy_groupids' => ['1'] } }

    before do
      allow(proxygroup_mock).to receive(:log)
      allow(client).to receive(:api_request).with(
        method: 'proxygroup.delete',
        params: data
      ).and_return(result)
    end

    context 'when result is not empty' do
      it 'returns the id of the first proxy group' do
        expect(subject).to eq 1
      end
    end

    context 'when result is empty' do
      let(:result) { [] }

      it { is_expected.to be_nil }
    end
  end
end
