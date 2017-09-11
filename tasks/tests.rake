require 'rake/testtask'

Rake::TestTask.new do |t|
  t.name = :test
  t.pattern = 'test/*_test.rb'
  t.options = '"--no-show_detail_immediately"'
  t.warning = false
end
