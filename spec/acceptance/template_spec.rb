require 'spec_helper'

describe 'template' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
  end

  context 'when name not exists' do
    before do
      @template = gen_name 'template'
    end

    describe 'create' do
      it 'should return integer id' do
        templateid = zbx.templates.create(
          host: @template,
          groups: [groupid: @hostgroupid]
        )
        expect(templateid).to be_kind_of(Integer)
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.templates.get_id(host: @template)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @template = gen_name 'template'
      @templateid = zbx.templates.create(
        host: @template,
        groups: [groupid: @hostgroupid]
      )
    end

    describe 'get_or_create' do
      it 'should return id of template' do
        expect(
          zbx.templates.get_or_create(
            host: @template,
            groups: [groupid: @hostgroupid]
          )
        ).to eq @templateid
      end
    end

    describe 'get_full_data' do
      it 'should contains created template' do
        expect(zbx.templates.get_full_data(host: @template)[0]).to include('host' => @template)
      end
    end

    describe 'get_id' do
      it 'should return id of template' do
        expect(zbx.templates.get_id(host: @template)).to eq @templateid
      end
    end

    describe 'all' do
      it 'should contains template' do
        expect(zbx.templates.all).to include(@template => @templateid.to_s)
      end
    end

    describe 'delete' do
      it 'should return id' do
        template = gen_name 'template'
        templateid = zbx.templates.create(
          host: template,
          groups: [groupid: @hostgroupid]
        )
        expect(zbx.templates.delete(templateid)).to eq templateid
      end
    end

    context 'host related operations' do
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

      context 'not linked with host' do
        describe 'mass_update' do
          it 'should return true' do
            expect(
              zbx.templates.mass_update(
                hosts_id: [@hostid],
                templates_id: [@templateid]
              )
            ).to be true
          end
        end
      end

      context 'linked with host' do
        before :all do
          zbx.templates.mass_update(
            hosts_id: [@hostid],
            templates_id: [@templateid]
          )
        end

        describe 'get_ids_by_host' do
          it 'should contains id of linked template' do
            tmpl_array = zbx.templates.get_ids_by_host(
              hostids: [@hostid]
            )
            expect(tmpl_array).to be_kind_of(Array)
            expect(tmpl_array).to include @templateid.to_s
          end
        end

        describe 'mass_add' do
          it 'should return true' do
            expect(
              zbx.templates.mass_add(
                hosts_id: [@hostid],
                templates_id: [@templateid]
              )
            ).to be_kind_of(TrueClass)
          end
        end

        describe 'mass_remove' do
          it 'should return true' do
            expect(
              zbx.templates.mass_remove(
                hosts_id: [@hostid],
                templates_id: [@templateid]
              )
            ).to be true
          end
        end
      end
    end
  end
end
