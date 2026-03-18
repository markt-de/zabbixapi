lib = File.expand_path('lib', __dir__)

$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'zabbixapi/version'

Gem::Specification.new do |spec|
  spec.add_dependency 'json', '~> 2.6'
  spec.add_development_dependency 'bundler', '>= 2.1'

  spec.name        = 'zabbixapi'
  spec.version     = ZabbixApi::VERSION
  spec.authors     = ['markt.de']
  spec.email       = ['github-oss-noreply@markt.de']

  spec.summary     = 'Ruby module for working with the Zabbix API'
  spec.description = 'Allows you to work with zabbix api from ruby.'
  spec.homepage    = 'https://github.com/markt-de/zabbixapi'
  spec.licenses    = 'MIT'

  spec.files         = ['CHANGELOG.md', 'LICENSE.md', 'README.md', 'zabbixapi.gemspec'] + Dir['lib/**/*.rb']
  spec.require_paths = 'lib'
  spec.required_ruby_version = '>= 3.3.0'
end
