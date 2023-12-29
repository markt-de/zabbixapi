require 'spec_helper'

describe 'script' do
  before :all do
    @hostid = zbx.hosts.get_id(host: 'Zabbix server')
  end

  context 'when name not exists' do
    before do
      @script = gen_name 'script'
    end

    describe 'create' do
      it 'should return integer id' do
        scriptid = zbx.scripts.create(
          name: @script,
          command: 'hostname'
        )
        expect(scriptid).to be_kind_of(Integer)
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.scripts.get_id(name: @script)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @script = gen_name 'script'
      @scriptid = zbx.scripts.create(
        name: @script,
        command: 'hostname'
      )
    end

    describe 'get_or_create' do
      it 'should return id of script' do
        expect(zbx.scripts.get_or_create(
                 name: @script,
                 command: 'hostname'
               )).to eq @scriptid
      end
    end

    describe 'get_full_data' do
      it 'should contains created script' do
        expect(zbx.scripts.get_full_data(name: @script)[0]).to include('name' => @script)
      end
    end

    describe 'get_id' do
      it 'should return id of script' do
        expect(zbx.scripts.get_id(name: @script)).to eq @scriptid
      end
    end

    it 'should raise error on no identity given' do
      expect { zbx.scripts.get_id({}) }.to raise_error(ZabbixApi::ApiError)
    end

    describe 'update' do
      it 'should return id' do
        expect(zbx.scripts.update(
                 scriptid: zbx.scripts.get_id(name: @script),
                 # enable_confirmation: 1,
                 confirmation: 'Are you sure you would like to show the system hostname?'
               )).to eq @scriptid
      end
    end

    describe 'create_or_update' do
      it 'should update existing script' do
        expect(zbx.scripts.get_or_create(
                 name: @script,
                 command: 'hostname'
               )).to eq @scriptid
      end

      it 'should create script' do
        new_script_id = zbx.scripts.get_or_create(
          name: @script + '____1',
          command: 'hostname'
        )

        expect(new_script_id).to be_kind_of(Integer)
        expect(new_script_id).to be > @scriptid
      end
    end

    # TODO: see if we can get this test working with travis ci (passes on standalone zabbix server)
    # describe 'execute' do
    #  it "should return success response" do
    #    expect(zbx.scripts.execute(:scriptid => @scriptid, :hostid => @hostid)).to include("response" => "success")
    #  end
    # end

    describe 'getscriptsbyhost' do
      it 'should return object with hostid and script' do
        expect(zbx.scripts.getscriptsbyhost([@hostid])[@hostid.to_s].select { |script| script[:name] == @script }).to_not be_nil
      end
    end

    describe 'delete' do
      before :all do
        @result = zbx.scripts.delete(@scriptid)
      end

      it 'should return deleted id' do
        expect(@result).to eq @scriptid
      end

      it 'should delete script from zabbix' do
        expect(zbx.scripts.get_id(name: @script)).to be_nil
      end
    end
  end
end
