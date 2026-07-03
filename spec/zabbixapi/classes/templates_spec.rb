require 'spec_helper'

describe 'ZabbixApi::Templates' do
  let(:templates_mock) { ZabbixApi::Templates.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { templates_mock.method_name }

    it { is_expected.to eq 'template' }
  end

  describe '.identify' do
    subject { templates_mock.identify }

    it { is_expected.to eq 'host' }
  end

  describe '.delete' do
    subject { templates_mock.delete(data) }

    let(:data) { { testidentify: 222 } }
    let(:result) { { 'templateids' => ['1'] } }
    let(:identify) { 'testidentify' }
    let(:method_name) { 'testmethod' }

    before do
      allow(templates_mock).to receive(:log)
      allow(client).to receive(:api_request).with(
        method: 'template.delete',
        params: [data]
      ).and_return(result)
    end

    context 'when result is not empty' do
      it 'returns the id of first template' do
        expect(subject).to eq 1
      end
    end

    context 'when result is empty' do
      let(:result) { [] }

      it { is_expected.to be_nil }
    end
  end

  describe '.get_ids_by_host' do
    subject { templates_mock.get_ids_by_host(data) }

    let(:data) { { scriptid: 222, hostid: 333 } }
    let(:result) { [{ 'templateid' => 1 }, { 'templateid' => 2 }] }
    let(:ids) { [1, 2] }

    before do
      allow(client).to receive(:api_request).with(
        method: 'template.get',
        params: data
      ).and_return(result)
    end

    it { is_expected.to eq ids }
  end

  describe '.get_or_create' do
    subject { templates_mock.get_or_create(data) }

    let(:data) { { host: 1234 } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(templates_mock).to receive(:get_id).with(host: data[:host]).and_return(id)
      allow(templates_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    context 'when ID already exist' do
      let(:id) { '111' }

      it 'returns the existing ID' do
        expect(subject).to eq id
      end
    end

    context 'when id does not exist' do
      it 'returns the newly created ID' do
        expect(subject).to eq id_through_create
      end
    end
  end

  describe '.mass_update' do
    subject { templates_mock.mass_update(data) }

    let(:data) { { hosts_id: [1234, 5678], templates_id: [1111, 2222] } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(client).to receive(:api_request).with(
        method: 'template.massUpdate',
        params: {
          templates: [{ templateid: 1111 }, { templateid: 2222 }]
        }
      ).and_return(result)
    end

    context 'when api_request returns empty result' do
      let(:result) { [] }

      it { is_expected.to be_falsy }
    end

    context 'when api_request doesn not return empty result' do
      it { is_expected.to be_truthy }
    end
  end

  describe '.mass_add' do
    subject { templates_mock.mass_add(data) }

    let(:data) { { hosts_id: [1234, 5678], templates_id: [1111, 2222] } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(client).to receive(:api_request).with(
        method: 'template.massAdd',
        params: {
          templates: [{ templateid: 1111 }, { templateid: 2222 }]
        }
      ).and_return(result)
    end

    context 'when api_request returns empty result' do
      let(:result) { [] }

      it { is_expected.to be_falsy }
    end

    context 'when api_request doesn not return empty result' do
      it { is_expected.to be_truthy }
    end
  end

  describe '.mass_remove' do
    subject { templates_mock.mass_remove(data) }

    let(:data) { { hosts_id: [1234, 5678], templates_id: [1111, 2222], group_id: 4545 } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(client).to receive(:api_request).with(
        method: 'template.massRemove',
        params: {
          templateids: data[:templates_id],
          groupids: data[:group_id]
        }
      ).and_return(result)
    end

    context 'when api_request returns empty result' do
      let(:result) { [] }

      it { is_expected.to be_falsy }
    end

    context 'when api_request doesn not return empty result' do
      it { is_expected.to be_truthy }
    end
  end
end
