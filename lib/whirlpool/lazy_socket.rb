module Whirlpool
  # Represents a socket that can be connected in the future.
  # The `read` and `write` methods will automatically try to
  # set-up the socket if it doesn't exist. If the socket is
  # `close`d, future writes will try to set up a new connection.
  class LazySocket
    def initialize &connect
      @connector = connect
      @connected = false
    end

    def connected?
      @socket
    end

    def write *args
      @socket = @connector.call unless connected?
      @socket.write *args
    end

    def read *args
      @socket = @connector.call unless connected?
      @socket.read *args
    end

    def close *args
      if connected?
        @socket.close *args
        @socket = nil
      end
    end
  end
end
