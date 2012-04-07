require 'rack'

class Rack::Process
  attr_reader :config_path

  def initialize config_path
    @config_path = config_path
    @config_path = ::File.join @config_path, "config.ru" if ::File.directory? @config_path
    @config_path = ::File.absolute_path @config_path

    raise ArgumentError, "Rackup file #{config_path} does not exist." unless ::File.exists? config_path

    at_exit { close }
  end

  def call env
    write "request"
    write JSON.encode env.reject { |key| key[/\A(?:rack|async)/] }

    status = headers = body = nil

    while status.nil?
      case command = read
      when "status"
        status = read.to_i
      when "input"
        write "input"
        write env["rack.input"].read
      when "error"
        raise Error, "Rack process error: #{JSON.decode(read).inspect}"
      else
        raise Error, "Expecting status, got #{command}"
      end
    end

    while headers.nil?
      case command = read
      when "headers"
        headers = JSON.decode read
      when "input"
        write "input"
        write env["rack.input"].read
      when "error"
        raise Error, "Rack process error: #{JSON.decode(read).inspect}"
      else
        raise Error, "Expecting headers, got #{command}"
      end
    end

    body = Enumerator.new do |body|
      while command = read
        case command
        when "output"
          body << read
        when "input"
          write "input"
          write env['rack.input'].read
        when "done"
          break
        when "error"
          raise Error, "Rack process error: #{JSON.decode(read).inspect}"
        else
          raise Error, "Expecting output, got #{command}"
        end
      end
    end

    [status, headers, body]
  end

protected

  def config_dir
    ::File.dirname(config_path)
  end

  def worker_path
    ::File.expand_path "../../../bin/rack-process-worker", __FILE__
  end

  def worker
    # TODO: Better process management
    @worker ||= IO.popen ["ruby", worker_path, config_path], "r+", chdir: config_dir, err: [:child, :err]
  end

  def read
    NetString.read worker
  end

  def write str
    NetString.write worker, str
  end

  def close
    write "close"
    ::Process.wait @worker.pid if @worker
  end
end

require 'rack/process/version'
require 'rack/process/error'
require 'rack/process/json'
require 'rack/process/net_string'
require 'rack/process/worker'
require 'rack/process/worker/rack_input'
