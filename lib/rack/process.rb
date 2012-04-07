require 'digest'
require 'fcntl'
require 'socket'
require 'stringio'
require 'strscan'

begin
  # Avoid activating json gem
  if defined? gem_original_require
    gem_original_require 'json'
  else
    require 'json'
  end
rescue LoadError
end

require 'rack'
require 'rack/builder'
require 'rack/rewindable_input'

require 'rack/process/version'

module Rack
  # This is an adaptation of Nack for pure-ruby usage
  class Process
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

    #def socket_path
    #  @socket_path ||= "#{Dir.tmpdir}/rack-process.#{::Process.pid}-#{Digest::SHA2.hexdigest config_path}-#{(rand * 10000000000).floor}.sock"
    #end

    class Error < StandardError
    end

    module JSON
      if defined? ::JSON
        def self.encode obj
          obj.to_json
        end

        def self.decode json
          ::JSON.parse json
        end
      else
        require 'okjson'

        def self.encode obj
          ::OkJson.encode obj
        end

        def self.decode json
          ::OkJson.decode json
        end
      end
    end

    # http://cr.yp.to/proto/netstrings.txt
    module NetString
    module_function

      def read io
        length = ns_length io.readline ":"
        buffer = io.read length

        if io.eof?
          return
        elsif io.getc != ?,
          raise Error, "Invalid netstring length, expected to be #{length}"
        end

        buffer
      end

      def write io, str
        io << "#{str.bytesize}:" << str << ","
        io.flush
      end

      def encode str
        io = StringIO.new
        write io, str
        io.string
      end

      def decode str
        io = StringIO.new str
        io.rewind
        read io
      end

    protected
    module_function

      def ns_length str
        s = StringScanner.new str

        if slen = s.scan(/\d+/)
          if slen =~ /^0\d+$/
            raise Error, "Invalid netstring with leading 0"
          elsif slen.length > 9
            raise Error, "netstring is too large"
          end

          len = Integer(slen)

          if s.scan(/:/)
            len
          elsif s.eos?
            raise Error, "Invalid netstring terminated after length"
          else
            raise Error, "Unexpected character '#{s.peek(1)}' found at offset #{s.pos}"
          end
        elsif s.peek(1) == ':'
          raise Error, "Invalid netstring with leading ':'"
        else
          raise Error, "Unexpected character '#{s.peek(1)}' found at offset #{s.pos}"
        end
      end
    end

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
        write "done"
      rescue SystemExit, Errno::EINTR
        # Ignore
      rescue Exception => e
        write "error"
        write JSON.encode 'name' => e.class.name,
          'message' => e.message,
          'stack' => e.backtrace.join("\n")
      end

      class RackInput
        include Enumerable

        def initialize worker
          @worker = worker
          @buffer = ""
          @position = 0
        end

        # A bunch of IO::Readable pilfered from http://git.tpope.net/ruby-io-mixins.git

        def read length=nil, buffer=""
          raise ArgumentError, "negative length #{length} given", caller if (length||0) < 0
          return "" if length == 0 && @buffer.length > 0
          return (length ? nil : "") if eof
          return "" if length == 0
          if length
            @buffer << sysread if @buffer.length<length
          else
            begin
              while str = sysread
                @buffer << str
              end
            rescue EOFError
              nil # For coverage
            end
          end
          buffer[0..-1] = @buffer.slice!(0..(length || 0)-1)
          @position ||= 0
          @position += buffer.length
          return buffer
        end

        def getc
          read(1).to_s[0]
        end

        def gets sep_string=$/
          return read(nil) unless sep_string
          line = ""
          paragraph = false
          if sep_string == ""
            sep_string = "\n\n"
            paragraph = true
          end
          sep = sep_string.dup
          position = @position
          while (char = getc)
            if paragraph && line.empty?
              if char == ?\n
                next
              end
            end
            if char == sep[0]
              sep[0] = ""
            else
              sep = sep_string.dup
            end
            if sep == ""
              if paragraph
                ungetc char
              else
                line << char
              end
              break
            end
            line << char
            if position && @position == position
              raise IOError, "loop encountered", caller
            end
          end
          line = nil if line == ""
          $_ = line
        end

        def each sep_string = $/
          while line = gets(sep_string)
            yield line
          end
          self
        end

        def eof
          return false unless @buffer.empty?
          str = sysread
          if str
            @buffer << str
            @buffer.empty?
          else
            true
          end
        rescue EOFError
          return true
        end

        alias eof? eof

        def close
        end

        def sysread
          @worker.write "input"
          case command = @worker.read
          when "input"
            return @worker.read
          when "close"
            exit
          else
            raise "Expected input, got #{command}"
          end
        end
      end
    end
  end
end
