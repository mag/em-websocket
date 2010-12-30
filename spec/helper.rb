require 'rubygems'
require 'rspec'
require 'pp'
require 'em-http'

require 'em-websocket'

Rspec.configure do |c|
  c.mock_with :rspec
end

class FakeWebSocketClient < EM::Connection
  attr_writer :onopen, :onclose, :onmessage
  attr_reader :handshake_response, :packets

  def initialize
    @state = :new
    @packets = []
  end

  def receive_data(data)
    # puts "RECEIVE DATA #{data}"
    if @state == :new
      @handshake_response = data
      @onopen.call if @onopen
      @state = :open
    else
      @onmessage.call(data) if @onmessage
      @packets << data
    end
  end

  def send(data)
    send_data("\x00#{data}\xff")
  end

  def unbind
    @onclose.call if @onclose
  end
end

def failed
  EventMachine.stop
  fail
end

def format_request(r)
  data = "#{r[:method]} #{r[:path]} HTTP/1.1\r\n"
  header_lines = r[:headers].map { |k,v| "#{k}: #{v}" }
  data << [header_lines, '', r[:body]].join("\r\n")
  data
end

def format_response(r)
  data = "HTTP/1.1 101 WebSocket Protocol Handshake\r\n"
  header_lines = r[:headers].map { |k,v| "#{k}: #{v}" }
  data << [header_lines, '', r[:body]].join("\r\n")
  data
end

def handler(request, secure = false)
  connection = Object.new
  EM::WebSocket::HandlerFactory.build(connection, format_request(request), secure)
end

RSpec::Matchers.define :send_handshake do |response|
  match do |actual|
    actual.handshake.lines.sort == format_response(response).lines.sort
  end
end

# Fake standard connection that sends back a 200 OK and closes the connection
class FakeStandardConnection
  attr_writer :actual_connection
  attr_reader :received_data

  def post_init;
  end

  def receive_data(data)
    @received_data ||= ""
    @received_data << data
    if @received_data.split("\n").last.strip == ""
      @actual_connection.send_data "HTTP/1.1 200 OK\r\n\r\nFAKE RESPONSE"
      @actual_connection.close_connection_after_writing
    end
  end
end

