# coding: utf-8

lib = File.expand_path('../lib', __FILE__)

$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'zabbixapi/version'

Gem::Specification.new do |spec|
  spec.add_dependency 'http', '~> 5.0'
  spec.add_dependency 'json', '~> 2.6'
  spec.add_development_dependency 'bundler'

  spec.name        = 'zabbixapi'
  spec.version     = ZabbixApi::VERSION
  spec.authors     = ['markt.de']
  spec.email       = ['github-oss-noreply@markt.de']

  spec.summary     = 'Simple and lightweight ruby module for working with the Zabbix API'
  spec.description = 'Allows you to work with zabbix api from ruby.'
  spec.homepage    = 'https://github.com/markt-de/zabbixapi'
  spec.licenses    = 'MIT'

  spec.rubyforge_project = 'zabbixapi'

  spec.files         = ['CHANGELOG.md', 'LICENSE.md', 'README.md', 'zabbixapi.gemspec'] + Dir['lib/**/*.rb']
  spec.require_paths = 'lib'
  spec.required_ruby_version = '>= 2.7.0'
end
