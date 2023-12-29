require 'spec_helper'

describe 'mediatype' do
  before do
    @mediatype = gen_name 'mediatype'
  end

  context 'when not exists' do
    describe 'create' do
      it 'should return integer id' do
        mediatypeid = zbx.mediatypes.create(
          name: @mediatype,
          type: 0,
          smtp_server: '127.0.0.1',
          smtp_email: 'zabbix@test.com',
          smtp_helo: 'test.com'
        )
        expect(mediatypeid).to be_kind_of(Integer)
      end
    end
  end

  context 'when exists' do
    before do
      @mediatypeid = zbx.mediatypes.create(
        name: @mediatype,
        type: 0,
        smtp_server: '127.0.0.1',
        smtp_email: 'zabbix@test.com',
        smtp_helo: 'test.com'
      )
    end

    describe 'create_or_update' do
      it 'should return id' do
        expect(
          zbx.mediatypes.create_or_update(
            name: @mediatype,
            smtp_email: 'zabbix2@test.com',
            smtp_helo: 'test.com'
          )
        ).to eq @mediatypeid
      end

      it 'should return id' do
        expect(@mediatypeid).to eq @mediatypeid
      end
    end
  end
end
