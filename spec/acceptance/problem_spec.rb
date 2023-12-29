require 'spec_helper'

describe 'problem' do
  before do
    @problemdata = {
      eventid: gen_id.to_s,
      source: "0",
      object: "0",
      objectid: gen_id.to_s,
      clock: "1611856476",
      ns: "183091100",
      r_eventid: "0",
      r_clock: "0",
      r_ns: "0",
      correlationid: "0",
      userid: "0",
      name: "Zabbix agent is not available (for 3m)",
      acknowledged: "0",
      severity: "3",
      opdata: "",
      acknowledges: [],
      suppression_data: [],
      suppressed: "0",
      urls: [],
      tags: []
    }
  end

  context 'when incorrect method' do
    describe 'create' do
      it 'should raise ApiError' do
        expect{zbx.problems.create({})}.
          to raise_error(ZabbixApi::ApiError, /.*\"data\": \"Incorrect method \\\"problem.create\\\"\.\"/)
      end
    end

    describe 'delete' do
      it 'should raise ApiError' do
        expect{zbx.problems.delete({})}.
          to raise_error(ZabbixApi::ApiError, /.*\"data\": \"Incorrect method \\\"problem.delete\\\"\.\"/)
      end
    end

    # describe 'update' do
    #   it 'should raise ApiError' do
    #     expect{zbx.problems.update({name: gen_name("problem")})}.
    #       to raise_error(ZabbixApi::ApiError, /.*\"data\": \"Incorrect method \\\"problem.update\\\"\.\"/)
    #   end
    # end
  end
end
