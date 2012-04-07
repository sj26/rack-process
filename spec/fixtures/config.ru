require 'rack-process'

run Rack::Process.new File.expand_path "../example-file.ru", __FILE__
