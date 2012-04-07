require 'rack/builder'
require 'rack/rewindable_input'

class Rack::Process
  class Worker
    def self.run *args
      new(*args).start
    end

    attr_accessor :config_path, :input, :output, :error

    def initialize config_path, input=$stdin, output=$stdout, error=$stderr
      self.config_path = config_path
      self.input = if input.is_a? String then File.open(input, 'r') else input end
      self.output = if output.is_a? String then File.open(output, 'w') else output end
      self.error = if error.is_a? String then File.open(error, 'w') else error end
    end

    def config
      ::File.read config_path
    end

    def app
      @app ||= eval "Rack::Builder.new {( #{config}\n )}.to_app", TOPLEVEL_BINDING, config_path
    end

    def read
      NetString.read input
    end

    def write str
      NetString.write output, str
    end

    def start
      trap('TERM') { exit }
      trap('INT')  { exit }
      trap('QUIT') { exit }

      input.set_encoding 'ASCII-8BIT' if input.respond_to? :set_encoding

      while not input.eof?
        case command = read
        when "request"
          handle_request JSON.decode read
        when "close"
          exit
        end
      end
    rescue SystemExit, Errno::EINTR
      # Ignore
    rescue Exception => e
      write "error"
      write JSON.encode 'name' => e.class.name,
        'message' => e.message,
        'stack' => e.backtrace.join("\n")
    end

    def handle_request env
      env = {
        "rack.version" => Rack::VERSION,
        "rack.input" => Rack::RewindableInput.new(RackInput.new(self)),
        "rack.errors" => error,
        "rack.multithread" => false,
        "rack.multiprocess" => true,
        "rack.run_once" => false,
        "rack.url_scheme" => ["yes", "on", "1"].include?(env["HTTPS"]) ? "https" : "http"
      }.merge(env)

      status, headers, body = app.call env

      write "status"
      write status.to_s
      write "headers"
      write JSON.encode headers
      body.each do |piece|
        write "output"
        write piece
      end
      body.close if body.respond_to? :close
      write "done"
    rescue SystemExit, Errno::EINTR
      # Ignore
    rescue Exception => e
      write "error"
      write JSON.encode 'name' => e.class.name,
        'message' => e.message,
        'stack' => e.backtrace.join("\n")
    end
  end
end
