require 'spec_helper'

describe 'screen' do
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
    @item = gen_name 'item'
    @itemid = zbx.items.create(
      name: @item,
      key_: "proc.num[#{gen_name 'proc'}]",
      status: 0,
      hostid: @templateid,
      applications: [@applicationid]
    )

    @color = '123456'

    @gitems = {
      itemid: @itemid,
      calc_fnc: '3',
      color: @color,
      type: '0',
      periods_cnt: '5'
    }

    @graph = gen_name 'graph'

    @graphid = zbx.graphs.create(
      gitems: [@gitems],
      show_triggers: '0',
      name: @graph,
      width: '900',
      height: '200'
    )

    @screen_name = gen_name 'screen'
  end

  context 'when not exists' do
    describe 'get_or_create_for_host' do
      it 'should return id' do
        screenid = zbx.screens.get_or_create_for_host(
          screen_name: @screen_name,
          graphids: [@graphid]
        )
        expect(screenid).to be_kind_of(Integer)
      end
    end
  end

  context 'when exists' do
    before do
      @screen_name = gen_name 'screen'
      @screenid = zbx.screens.get_or_create_for_host(
        screen_name: @screen_name,
        graphids: [@graphid]
      )
    end

    describe 'get_or_create_for_host' do
      it 'should return id' do
        screenid = zbx.screens.get_or_create_for_host(
          screen_name: @screen_name,
          graphids: [@graphid]
        )
        expect(screenid).to eq @screenid
      end
    end

    describe 'delete' do
      it 'should return id' do
        expect(zbx.screens.delete(@screenid)).to eq @screenid
      end
    end
  end
end
