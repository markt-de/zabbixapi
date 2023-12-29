require 'spec_helper'

describe 'item' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
    @template = gen_name 'template'
    @templateid = zbx.templates.create(
      host: @template,
      groups: [groupid: @hostgroupid]
    )
    @application = gen_name 'application'
    @applicationid = zbx.applications.create(
      name: @application,
      hostid: @templateid
    )
  end

  context 'when name not exists' do
    before do
      @item = gen_name 'item'
    end

    describe 'create' do
      it 'should return integer id' do
        itemid = zbx.items.create(
          name: @item,
          key_: "proc.num[#{gen_name 'proc'}]",
          status: 0,
          hostid: @templateid,
          applications: [@applicationid]
        )
        expect(itemid).to be_kind_of(Integer)
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.items.get_id(name: @item)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @item = gen_name 'item'
      @itemid = zbx.items.create(
        name: @item,
        key_: 'proc.num[aaa]',
        status: 0,
        hostid: @templateid,
        applications: [@applicationid]
      )
    end

    describe 'get_or_create' do
      it 'should return id of item' do
        expect(
          zbx.items.get_or_create(
            name: @item,
            key_: "proc.num[#{gen_name 'proc'}]",
            status: 0,
            hostid: @templateid,
            applications: [@applicationid]
          )
        ).to eq @itemid
      end
    end

    describe 'get_full_data' do
      it 'should contains created item' do
        expect(zbx.items.get_full_data(name: @item)[0]).to include('name' => @item)
      end
    end

    describe 'get_id' do
      it 'should return id of item' do
        expect(zbx.items.get_id(name: @item)).to eq @itemid
      end
    end

    it 'should raise error on no identity given' do
      expect { zbx.items.get_id({}) }.to raise_error(ZabbixApi::ApiError)
    end

    describe 'update' do
      it 'should return id' do
        expect(
          zbx.items.update(
            itemid: zbx.items.get_id(name: @item),
            status: 1
          )
        ).to eq @itemid
      end
    end

    describe 'create_or_update' do
      it 'should update existing item' do
        expect(
          zbx.items.create_or_update(
            name: @item,
            key_: "proc.num[#{gen_name 'proc'}]",
            status: 0,
            hostid: @templateid,
            applications: [@applicationid]
          )
        ).to eq @itemid
      end

      it 'should create item' do
        new_item_id = zbx.items.create_or_update(
          name: @item + '____1',
          key_: "proc.num[#{gen_name 'proc'}]",
          status: 0,
          hostid: @templateid,
          applications: [@applicationid]
        )

        expect(new_item_id).to be_kind_of(Integer)
        expect(new_item_id).to be > @itemid
      end
    end

    describe 'delete' do
      before :all do
        @result = zbx.items.delete(@itemid)
      end

      it 'should return deleted id' do
        expect(@result).to eq @itemid
      end

      it 'should delete item from zabbix' do
        expect(zbx.items.get_id(name: @item)).to be_nil
      end
    end
  end
end
