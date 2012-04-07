class Rack::Process
  class Worker::RackInput
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
