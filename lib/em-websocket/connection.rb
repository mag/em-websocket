require 'addressable/uri'

module EventMachine
  module WebSocket
    class Connection < EventMachine::Connection
      include Debugger

      # define WebSocket callbacks
      def onopen(&blk);     @onopen = blk;    end
      def onclose(&blk);    @onclose = blk;   end
      def onerror(&blk);    @onerror = blk;   end
      def onmessage(&blk);  @onmessage = blk; end

      def trigger_on_message(msg)
        @onmessage.call(msg) if @onmessage
      end
      def trigger_on_open
        @onopen.call if @onopen
      end
      def trigger_on_close
        @onclose.call if @onclose
      end

      def initialize(options)
        @options = options
        @debug = options[:debug] || false
        @secure = options[:secure] || false
        @tls_options = options[:tls_options] || {}
        @request = {}
        @data = ''

        debug [:initialize]
      end

      # Use this method to close the websocket connection cleanly
      # This sends a close frame and waits for acknowlegement before closing
      # the connection
      def close_websocket
        if @handler
          @handler.close_websocket
        else
          # The handshake hasn't completed - should be safe to terminate
          close_connection
        end
      end

      def post_init
        start_tls(@tls_options) if @secure
      end

      def receive_data(data)
        debug [:receive_data, data]
        if complete_header_received?(data) && is_standard_http?(data)
          proxy_class = @options[:standard_connection_class]
          proxy = proxy_class.new
          if !@standard_connection_initialized
            proxy.actual_connection = self
            proxy.post_init
            @standard_connection_initialized = true
          end
          proxy.receive_data(data)
          return
        end
        if @handler
          @handler.receive_data(data)
        else
          dispatch(data)
        end
      end

      def unbind
        debug [:unbind, :connection]

        @handler.unbind if @handler
      end

      def parse_out_headers_and_body(data)
        data.split("\r\n\r\n", 2)
      end

      def complete_header_received?(data)
        (header, remains) = parse_out_headers_and_body(data)
        !remains.nil?
      end

      def is_standard_http?(data)
        unless complete_header_received?(data)
          raise "Cannot determine if this is standard HTTP until all headers received"
        end

        (header, remains) = parse_out_headers_and_body(data)
        begin
          request = request_hash_from_headers(header)
          !(request['Connection'] == 'Upgrade' and request['Upgrade'] == 'WebSocket')
        rescue HandshakeError
          false
        end
      end

      PATH   = /^(\w+) (\/[^\s]*) HTTP\/1\.1$/
      HEADER = /^([^:]+):\s*(.+)$/

      def request_hash_from_headers(headers)
        # ripped off from HandlerFactory. TODO: combine.
        request = {}
        lines = headers.split("\r\n")

        # extract request path
        first_line = lines.shift.match(PATH)
        raise HandshakeError, "Invalid HTTP header" unless first_line
        request['Method'] = first_line[1].strip
        request['Path'] = first_line[2].strip

        unless request["Method"] == "GET"
          raise HandshakeError, "Must be GET request"
        end

        # extract query string values
        request['Query'] = Addressable::URI.parse(request['Path']).query_values ||= {}
        # extract remaining headers
        lines.each do |line|
          h = HEADER.match(line)
          request[h[1].strip] = h[2].strip if h
        end

        request
      end

      def dispatch(data)
        if data.match(/\A<policy-file-request\s*\/>/)
          send_flash_cross_domain_file
          return false
        else
          debug [:inbound_headers, data]
          begin
            @data << data
            @handler = HandlerFactory.build(self, @data, @secure, @debug)
            unless @handler
              # The whole header has not been received yet.
              return false
            end
            @data = nil
            @handler.run
            return true
          rescue => e
            debug [:error, e]
            process_bad_request(e)
            return false
          end
        end
      end

      def process_bad_request(reason)
        @onerror.call(reason) if @onerror
        send_data "HTTP/1.1 400 Bad request\r\n\r\n"
        close_connection_after_writing
      end

      def send_flash_cross_domain_file
        file =  '<?xml version="1.0"?><cross-domain-policy><allow-access-from domain="*" to-ports="*"/></cross-domain-policy>'
        debug [:cross_domain, file]
        send_data file

        # handle the cross-domain request transparently
        # no need to notify the user about this connection
        @onclose = nil
        close_connection_after_writing
      end

      def send(data)
        debug [:send, data]

        if @handler
          @handler.send_text_frame(data)
        else
          raise WebSocketError, "Cannot send data before onopen callback"
        end
      end

      def close_with_error(message)
        @onerror.call(message) if @onerror
        close_connection_after_writing
      end

      def request
        @handler ? @handler.request : {}
      end

      def state
        @handler ? @handler.state : :handshake
      end
    end
  end
end
