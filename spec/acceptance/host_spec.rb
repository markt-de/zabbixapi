require 'spec_helper'

describe 'host' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
  end

  context 'when name not exists' do
    before do
      @host = gen_name 'host'
    end

    describe 'create' do
      it 'should return integer id' do
        hostid = zbx.hosts.create(
          host: @host,
          interfaces: [
            {
              type: 1,
              main: 1,
              ip: '10.20.48.88',
              dns: '',
              port: '10050',
              useip: 1
            }
          ],
          groups: [groupid: @hostgroupid]
        )
        expect(hostid).to be_kind_of(Integer)
      end

      it 'should create host in multiple groups' do
        @hostgroupid2 = zbx.hostgroups.create(name: gen_name('hostgroup'))
        host = gen_name('host')
        hostid = zbx.hosts.create(
          host: host,
          interfaces: [
            {
              type: 1,
              main: 1,
              ip: '192.168.0.1',
              dns: 'server.example.org',
              port: '10050',
              useip: 0
            }
          ],
          groups: [
            { groupid: @hostgroupid },
            { groupid: @hostgroupid2 }
          ]
        )

        expect(hostid).to be_kind_of Integer
        host = zbx.query(method: 'host.get', params: { hostids: [hostid], selectGroups: 'extend' }).first

        expect(host['hostid'].to_i).to eq hostid
        expect(host['groups'].size).to eq 2
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.hosts.get_id(host: @host)).to be_kind_of(NilClass)
        expect(zbx.hosts.get_id('host' => @host)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @host = gen_name 'host'
      @hostid = zbx.hosts.create(
        host: @host,
        interfaces: [
          {
            type: 1,
            main: 1,
            ip: '10.20.48.88',
            dns: '',
            port: '10050',
            useip: 1
          }
        ],
        groups: [groupid: @hostgroupid]
      )
    end

    describe 'get_or_create' do
      it 'should return id of host' do
        expect(
          zbx.hosts.get_or_create(
            host: @host,
            groups: [groupid: @hostgroupid]
          )
        ).to eq @hostid
      end
    end

    describe 'get_full_data' do
      it 'should contains created host' do
        expect(zbx.hosts.get_full_data(host: @host)[0]).to include('host' => @host)
      end
    end

    describe 'get_id' do
      it 'should return id of host' do
        expect(zbx.hosts.get_id(host: @host)).to eq @hostid
        expect(zbx.hosts.get_id('host' => @host)).to eq @hostid
      end
    end

    describe 'create_or_update' do
      it 'should return id of updated host' do
        expect(
          zbx.hosts.create_or_update(
            host: @host,
            interfaces: [
              {
                type: 1,
                main: 1,
                ip: '10.20.48.89',
                port: '10050',
                useip: 1,
                dns: ''
              }
            ],
            groups: [groupid: @hostgroupid]
          )
        ).to eq @hostid
      end
    end

    describe 'update' do
      it 'should return id' do
        expect(
          zbx.hosts.update(
            hostid: @hostid,
            status: 0
          )
        ).to eq @hostid
      end

      it 'should update groups' do
        @hostgroupid2 = zbx.hostgroups.create(name: gen_name('hostgroup'))

        expect(
          zbx.hosts.update(
            hostid: @hostid,
            groups: [groupid: @hostgroupid2]
          )
        ).to eq @hostid

        expect(zbx.hosts.dump_by_id(hostid: @hostid).first['groups'].first['groupid']).to eq @hostgroupid2.to_s
      end

      it 'should update interfaces when use with force: true' do
        new_ip = '1.2.3.4'
        zbx.hosts.update(
          {
            hostid: @hostid,
            interfaces: [
              {
                type: 1,
                main: 1,
                ip: new_ip,
                port: '10050',
                useip: 1,
                dns: ''
              }
            ]
          },
          true
        )

        h = zbx.query(
          method: 'host.get',
          params: {
            hostids: @hostid,
            selectInterfaces: 'extend'
          }
        ).first

        expect(h['interfaces'].first['ip']).to eq new_ip
      end
    end

    describe 'delete' do
      it 'HOST: Delete' do
        expect(zbx.hosts.delete(@hostid)).to eq @hostid
      end
    end
  end
end
