require 'spec_helper'

describe 'ZabbixApi::Users' do
  let(:users_mock) { ZabbixApi::Users.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { users_mock.method_name }

    it { is_expected.to eq 'user' }
  end

  describe '.identify' do
    subject { users_mock.identify }

    it { is_expected.to eq 'username' }
  end

  describe '.key' do
    subject { users_mock.key }

    it { is_expected.to eq 'userid' }
  end

  describe '.keys' do
    subject { users_mock.keys }

    it { is_expected.to eq 'userids' }
  end

  describe '.medias_helper' do
    subject { users_mock.medias_helper(data, action) }

    let(:data) { { userids: [1234, 5678], media: 'testmedia' } }
    # let(:result) { { 'mediaids' => ['111'], 'testidentify' => 1 } }
    let(:result) { { 'userids' => ['111'] } }
    let(:action) { 'updateMedia' }

    before do
      users = data[:userids].map do |t|
        {
          userid: t,
          medias: data[:media]
        }
      end
      allow(client).to receive(:api_request).with(
        method: "user.#{action}",
        params: users
      ).and_return(result)
    end

    context 'when api_request returns nil result' do
      let(:result) { nil }

      it { is_expected.to be_nil }
    end

    context 'when api_request does not return empty result' do
      it 'returns first mediaid' do
        expect(subject).to eq 111
      end
    end
  end

  describe '.add_medias' do
    subject { users_mock.add_medias(data) }

    let(:data) { { userids: [1234, 5678], media: 'testmedia' } }
    let(:result) { { 'userids' => ['111'], 'testidentify' => 1 } }

    before do
      allow(users_mock).to receive(:medias_helper)
    end

    it 'calls medias_helper' do
      expect(users_mock).to receive(:medias_helper).with(
        data,
        'update'
      )
      subject
    end
  end

  describe '.update_medias' do
    subject { users_mock.update_medias(data) }

    let(:data) { { userids: [1234, 5678], media: 'testmedia' } }
    let(:result) { { 'userids' => ['111'], 'testidentify' => 1 } }

    before do
      allow(users_mock).to receive(:medias_helper)
    end

    it 'calls medias_helper' do
      expect(users_mock).to receive(:medias_helper).with(
        data,
        'update'
      )
      subject
    end
  end
end
