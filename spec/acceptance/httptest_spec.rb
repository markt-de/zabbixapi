require 'spec_helper'

describe 'httptest' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
    @template = gen_name 'template'
    @templateid = zbx.templates.create(
      host: @template,
      groups: [groupid: @hostgroupid]
    )
  end

  context 'when name not exists' do
    before do
      @httptest_name = gen_name 'httptest_name'
      @step_name = gen_name 'step_name'
    end

    describe 'create' do
      it 'should return integer id' do
        httptestid = zbx.httptests.create(
          name: @httptest_name,
          hostid: @templateid,
          steps: [
            {
              name: @step_name,
              url: 'http://localhost/zabbix/',
              status_codes: '200',
              no: 1
            }
          ]
        )
        expect(httptestid).to be_kind_of(Integer)
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.httptests.get_id(name: @httptest_name)).to be_kind_of(NilClass)
        expect(zbx.httptests.get_id('name' => @httptest_name)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @httptest_name = gen_name 'httptest_name'
      @step_name = gen_name 'step_name'
      @httptestid = zbx.httptests.create(
        name: @httptest_name,
        hostid: @templateid,
        steps: [
          {
            name: @step_name,
            url: 'http://localhost/zabbix/',
            status_codes: '200',
            no: 1
          }
        ]
      )
    end

    describe 'get_or_create' do
      it 'should return id of httptest' do
        expect(
          zbx.httptests.get_or_create(
            name: @httptest_name,
            hostid: @templateid,
            steps: [
              {
                name: @step_name,
                url: 'http://localhost/zabbix/',
                status_codes: '200',
                no: 1
              }
            ]
          )
        ).to eq @httptestid
      end
    end

    describe 'get_full_data' do
      it 'should contain created httptest' do
        expect(zbx.httptests.get_full_data(name: @httptest_name)[0]).to include('name' => @httptest_name)
      end
    end

    describe 'get_id' do
      it 'should return id of httptest' do
        expect(zbx.httptests.get_id(name: @httptest_name)).to eq @httptestid
        expect(zbx.httptests.get_id('name' => @httptest_name)).to eq @httptestid
      end
    end

    describe 'create_or_update' do
      it 'should return id of updated httptest' do
        expect(
          zbx.httptests.create_or_update(
            name: @httptest_name,
            hostid: @templateid,
            steps: [
              {
                name: @step_name,
                url: 'http://localhost/zabbix/',
                status_codes: '200',
                no: 1
              }
            ]
          )
        ).to eq @httptestid
      end
    end

    describe 'update' do
      it 'should return id' do
        expect(
          zbx.httptests.update(
            httptestid: @httptestid,
            status: 0,
            steps: [
              {
                name: @step_name,
                url: 'http://localhost/zabbix/',
                status_codes: '200',
                no: 1
              }
            ]
          )
        ).to eq @httptestid
      end
    end

    describe 'delete' do
      it 'HTTPTEST: Delete' do
        expect(zbx.httptests.delete(@httptestid)).to eq @httptestid
      end
    end
  end
end
