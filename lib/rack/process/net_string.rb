require 'stringio'
require 'strscan'

class Rack::Process
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
end
