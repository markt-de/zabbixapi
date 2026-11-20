require 'json'

# The recorded exchanges under spec/fixtures/<class>/<scenario>.json, addressed as 'hostgroups/crud'.
module Fixtures
  ROOT = File.expand_path('../fixtures', __dir__)

  class << self
    def path(name)
      File.join(ROOT, "#{name}.json")
    end

    def load(name)
      JSON.parse(File.read(path(name)))
    end

    def exchanges(name)
      load(name).fetch('exchanges')
    end

    def exchange(name, method, index = 0)
      found = exchanges(name).select { |exchange| exchange['method'] == method }
      found.fetch(index) { raise ArgumentError.new("#{name} has no #{method} exchange at index #{index}") }
    end
  end
end
