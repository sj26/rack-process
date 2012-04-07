run proc do |env|
  [200, {}, "Hello, #{env['HTTP_X_NAME'] || "world"}, from example-dir/config.ru"]
end
