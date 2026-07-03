require 'spec_helper'

describe 'ZabbixApi::Usergroups' do
  let(:usergroups_mock) { ZabbixApi::Usergroups.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { usergroups_mock.method_name }

    it { is_expected.to eq 'usergroup' }
  end

  describe '.identify' do
    subject { usergroups_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.key' do
    subject { usergroups_mock.key }

    it { is_expected.to eq 'usrgrpid' }
  end

  describe '.permissions' do
    subject { usergroups_mock.permissions(data) }

    let(:data) { { permission: permission, usrgrpid: 123, hostgroupids: [4, 5] } }
    let(:result) { { 'usrgrpids' => [9090] } }
    let(:key) { 'testkey' }
    let(:permission) { 3 }

    before do
      rights = data[:hostgroupids].map do |t|
        {
          id: t,
          permission: data[:permission]
        }
      end
      user_groups = {
        rights: rights,
        usrgrpid: data[:usrgrpid]
      }
      nil_rights = data[:hostgroupids].map do |t|
        {
          id: t,
          permission: 2
        }
      end
      nil_user_group = {
        rights: nil_rights,
        usrgrpid: data[:usrgrpid]
      }
      allow(usergroups_mock).to receive(:log)
      allow(usergroups_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: 'usergroup.update',
        params: user_groups
      ).and_return(result)
      allow(client).to receive(:api_request).with(
        method: 'usergroup.update',
        params: nil_user_group
      ).and_return(result)
    end

    context 'when permission is provided in data' do
      it 'uses permission provided in data' do
        expect(client).to receive(:api_request).with(
          method: 'usergroup.update',
          params: {
            usrgrpid: data[:usrgrpid],
            rights: data[:hostgroupids].map { |t| { permission: permission, id: t } }
          }
        )
        subject
      end

      it 'returns first usrgrpid' do
        expect(subject).to eq 9090
      end
    end

    context 'when permission is not provided in data' do
      let(:data) { { usrgrpid: 123, hostgroupids: [4, 5] } }
      let(:permission) { 2 }

      it 'uses permission provided in data' do
        expect(client).to receive(:api_request).with(
          method: 'usergroup.update',
          params: {
            usrgrpid: data[:usrgrpid],
            rights: data[:hostgroupids].map { |t| { permission: permission, id: t } }
          }
        )
        subject
      end

      it 'returns first usrgrpid' do
        expect(subject).to eq 9090
      end
    end

    context 'when api returns nil result' do
      let(:result) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '.add_user' do
    subject { usergroups_mock.add_user(data) }

    let(:data) { { userids: [123, 111], usrgrpids: [4, 5] } }
    let(:result) { { 'usrgrpids' => [9090] } }
    let(:key) { 'testkey' }
    let(:permission) { 3 }

    before do
      user_groups = data[:usrgrpids].map do |t|
        {
          users: data[:userids],
          usrgrpid: t
        }
      end
      allow(usergroups_mock).to receive(:log)
      allow(usergroups_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: 'usergroup.update',
        params: user_groups
      ).and_return(result)
    end

    context 'when returns result with usergroups' do
      it 'returns first usrgrpid' do
        expect(subject).to eq 9090
      end
    end

    context 'when api returns nil result' do
      let(:result) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '.update_users' do
    subject { usergroups_mock.update_users(data) }

    let(:data) { { userids: [123, 111], usrgrpids: [4, 5] } }
    let(:result) { { 'usrgrpids' => [9090] } }
    let(:key) { 'testkey' }
    let(:permission) { 3 }

    before do
      user_groups = data[:usrgrpids].map do |t|
        {
          users: data[:userids],
          usrgrpid: t
        }
      end
      allow(usergroups_mock).to receive(:log)
      allow(usergroups_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: 'usergroup.update',
        params: user_groups
      ).and_return(result)
    end

    context 'when returns result with usergroups' do
      it 'returns first usrgrpid' do
        expect(subject).to eq 9090
      end
    end

    context 'when api returns nil result' do
      let(:result) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end
end
