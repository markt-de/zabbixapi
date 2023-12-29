require 'spec_helper'

describe 'server' do
  describe 'version' do
    it 'should be string' do
      expect(zbx.server.version).to be_kind_of(String)
    end

    it 'should be 2.4.x, 3.2.x, 3.4.x, 4.0.x, 5.0.x, or 5.2.x' do
      expect(zbx.server.version).to match(/(2\.4|3\.[024]|4\.0|5\.[02])\.\d+/)
    end
  end
end
