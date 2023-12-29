require 'spec_helper'

describe 'graph' do
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
  end

  def gitems
    {
      itemid: @itemid,
      calc_fnc: '3',
      color: @color,
      type: '0',
      periods_cnt: '5'
    }
  end

  def create_graph(graph, _itemid)
    zbx.graphs.create(
      gitems: [gitems],
      show_triggers: '0',
      name: graph,
      width: '900',
      height: '200'
    )
  end

  context 'when name not exists' do
    describe 'create' do
      it 'should return integer id' do
        @graph = gen_name 'graph'
        expect(create_graph(@graph, @itemid)).to be_kind_of(Integer)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @graph = gen_name 'graph'
      @graphid = create_graph(@graph, @itemid)
    end

    describe 'get_or_create' do
      it 'should return id of existing graph' do
        expect(
          zbx.graphs.get_or_create(
            gitems: [gitems],
            show_triggers: '0',
            name: @graph,
            width: '900',
            height: '200'
          )
        ).to eq @graphid
      end
    end

    describe 'get_items' do
      it 'should return array' do
        expect(zbx.graphs.get_items(@graphid)).to be_kind_of(Array)
      end

      it 'should return array of size 1' do
        expect(zbx.graphs.get_items(@graphid).size).to eq 1
      end

      it 'should include correct item' do
        expect(zbx.graphs.get_items(@graphid)[0]).to include('color' => @color)
      end
    end

    describe 'get_id' do
      it 'should return id' do
        expect(zbx.graphs.get_id(name: @graph)).to eq @graphid
      end
    end

    describe 'get_ids_by_host' do
      it 'should contains id of graph' do
        graph_array = zbx.graphs.get_ids_by_host(host: @host)
        expect(graph_array).to be_kind_of(Array)
        expect(graph_array).to include(@graphid.to_s)
      end
    end

    describe 'update' do
      it 'should return id' do
        expect(
          zbx.graphs.update(
            graphid: @graphid,
            gitems: [gitems],
            ymax_type: 1
          )
        ).to eq @graphid
      end
    end

    describe 'create_or_update' do
      it 'should return existing id' do
        expect(
          zbx.graphs.create_or_update(
            gitems: [gitems],
            show_triggers: '1',
            name: @graph,
            width: '900',
            height: '200'
          )
        ).to eq @graphid
      end
    end

    describe 'delete' do
      it 'should return true' do
        expect(zbx.graphs.delete(@graphid)).to eq @graphid
      end
    end
  end
end
