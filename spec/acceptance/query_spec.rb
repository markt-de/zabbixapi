require 'spec_helper'

describe 'query' do
  it 'should works' do
    expect(
      zbx.query(
        method: 'host.get',
        params: {
          filter: {
            host: 'asdf'
          },
          selectInterfaces: 'refer'
        }
      )
    ).to be_kind_of(Array)
  end
end
