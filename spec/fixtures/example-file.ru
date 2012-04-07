require 'rack'

run(proc do |env|
  request = Rack::Request.new env
  [200, {"Content-Type" => "text/html"}, [%{<!DOCTYPE html>\n<html><head><title>Example File</title></head><body><p>Hello, #{request.POST['name'] || "world"}, from example-file.ru</p><form method="POST"><input name="name" placeholder="Name"> <button>Know Me</button></form></body></html>}]]
end)
