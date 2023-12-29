require 'spec_helper'

describe 'usermacro' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
    @template = gen_name 'template'
    @templateid = zbx.templates.create(
      host: @template,
      groups: [groupid: @hostgroupid]
    )
  end

  context 'when hostmacro not exists' do
    before do
      @hostmacro = '{$' + gen_name('HOSTMACRO') + '}'
    end

    describe 'create' do
      it 'should return integer id' do
        hostmacroid = zbx.usermacros.create(
          macro: @hostmacro,
          value: 'public',
          hostid: @templateid
        )
        expect(hostmacroid).to be_kind_of(Integer)
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.usermacros.get_id(macro: @hostmacro)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when hostmacro exists' do
    before :all do
      @hostmacro = '{$' + gen_name('HOSTMACRO') + '}'
      @hostmacroid = zbx.usermacros.create(
        macro: @hostmacro,
        value: 'public',
        hostid: @templateid
      )
    end

    describe 'get_or_create' do
      it 'should return id of hostmacro' do
        expect(
          zbx.usermacros.get_or_create(
            macro: @hostmacro,
            value: 'public',
            hostid: @templateid
          )
        ).to eq @hostmacroid
      end
    end

    describe 'get_full_data' do
      it 'should contains created hostmacro' do
        expect(zbx.usermacros.get_full_data(macro: @hostmacro)[0]).to include('macro' => @hostmacro)
      end
    end

    describe 'get_id' do
      it 'should return id of hostmacro' do
        expect(zbx.usermacros.get_id(macro: @hostmacro)).to eq @hostmacroid
      end
    end

    it 'should raise error on no identity given' do
      expect { zbx.usermacros.get_id({}) }.to raise_error(ZabbixApi::ApiError)
    end

    describe 'update' do
      it 'should return id' do
        expect(
          zbx.usermacros.update(
            hostmacroid: zbx.usermacros.get_id(
              macro: @hostmacro
            ),
            value: 'private'
          )
        ).to eq @hostmacroid
      end
    end

    describe 'create_or_update' do
      it 'should update existing usermacro' do
        expect(
          zbx.usermacros.create_or_update(
            macro: @hostmacro,
            value: 'public',
            hostid: @templateid
          )
        ).to eq @hostmacroid
      end

      it 'should create usermacro' do
        new_hostmacro_id = zbx.usermacros.create_or_update(
          macro: @hostmacro.gsub(/}/, '____1}'),
          value: 'public',
          hostid: @templateid
        )

        expect(new_hostmacro_id).to be_kind_of(Integer)
        expect(new_hostmacro_id).to be > @hostmacroid
      end
    end

    describe 'delete' do
      before :all do
        @result = zbx.usermacros.delete(@hostmacroid)
      end

      it 'should return deleted id' do
        expect(@result).to eq @hostmacroid
      end

      it 'should delete item from zabbix' do
        expect(zbx.usermacros.get_id(macro: @hostmacro)).to be_nil
      end
    end
  end

  context 'when globalmacro not exists' do
    before do
      @globalmacro = '{$' + gen_name('GLOBALMACRO') + '}'
    end

    describe 'create_global' do
      it 'should return integer id' do
        globalmacroid = zbx.usermacros.create_global(
          macro: @globalmacro,
          value: 'public'
        )
        expect(globalmacroid).to be_kind_of(Integer)
      end
    end

    describe 'get_id_global' do
      it 'should return nil' do
        expect(zbx.usermacros.get_id_global(macro: @globalmacro)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when globalmacro exists' do
    before :all do
      @globalmacro = '{$' + gen_name('GLOBALMACRO') + '}'
      @globalmacroid = zbx.usermacros.create_global(
        macro: @globalmacro,
        value: 'public'
      )
    end

    describe 'get_full_data_global' do
      it 'should contains created globalmacro' do
        expect(zbx.usermacros.get_full_data_global(macro: @globalmacro)[0]).to include('macro' => @globalmacro)
      end
    end

    describe 'get_id_global' do
      it 'should return id of globalmacro' do
        expect(zbx.usermacros.get_id_global(macro: @globalmacro)).to eq @globalmacroid
      end
    end

    it 'should raise error on no identity given' do
      expect { zbx.usermacros.get_id_global({}) }.to raise_error(ZabbixApi::ApiError)
    end

    describe 'update_global' do
      it 'should return id' do
        expect(
          zbx.usermacros.update_global(
            globalmacroid: zbx.usermacros.get_id_global(
              macro: @globalmacro
            ),
            value: 'private'
          )
        ).to eq @globalmacroid
      end
    end

    describe 'delete_global' do
      before :all do
        @result = zbx.usermacros.delete_global(@globalmacroid)
      end

      it 'should return deleted id' do
        expect(@result).to eq @globalmacroid
      end

      it 'should delete item from zabbix' do
        expect(zbx.usermacros.get_id_global(macro: @globalmacro)).to be_nil
      end
    end
  end
end
