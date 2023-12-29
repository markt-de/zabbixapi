require 'bundler'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

task test: :spec

require 'rubocop/rake_task'
RuboCop::RakeTask.new

require 'yard'
YARD::Rake::YardocTask.new

task default: [:spec, :rubocop]

begin
  require 'yardstick/rake/measurement'
  Yardstick::Rake::Measurement.new do |measurement|
    measurement.output = 'measurement/report.txt'
  end

  require 'yardstick/rake/verify'
  Yardstick::Rake::Verify.new do |verify|
    verify.threshold = 67.1
  end

  Rake::Task[:default].enhance(:verify_measurements)
rescue LoadError
  # yardstick not present
end
