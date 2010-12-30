require 'spec/helper'

describe EventMachine::WebSocket::Connection do

  context "when a standard HTTP request comes in" do
    it "forwards the data to the given standard connection" do
      instance = FakeStandardConnection.new
      FakeStandardConnection.stub(:new) {instance}
      conn = EventMachine::WebSocket::Connection.new(1, {:standard_connection_class => FakeStandardConnection})
      conn.stub!(:send_data)
      conn.stub!(:close_connection_after_writing)
      request = "GET / HTTP/1.1\r\nUser-Agent: EventMachine HttpClient\r\nHost: 127.0.0.1:12345\r\n\r\n"
      conn.receive_data(request)
      instance.received_data.should == request
    end

    context "and when the entire header is not received in one chunk" do
      before do
        @full_request = "GET / HTTP/1.1\r\nUser-Agent: EventMachine HttpClient\r\nHost: 127.0.0.1:12345\r\n\r\n"
      end

      context "before the whole header is received" do
        it "should not send initialize the upstream connection, nor send any data to it" do
          instance = FakeStandardConnection.new
          FakeStandardConnection.stub(:new) {instance}
          instance.should_not_receive(:post_init)
          instance.should_not_receive(:receive_data)
          conn = EventMachine::WebSocket::Connection.new(1, {:standard_connection_class => FakeStandardConnection})
          request = "GET / HTTP/1.1"
          conn.receive_data(request)
        end
      end

      context "once the whole header is received" do
        it "should initialize the upstream connection and send the data to it" do
          instance = FakeStandardConnection.new
          FakeStandardConnection.stub!(:new) {instance}
          instance.should_receive(:post_init)
          conn = EventMachine::WebSocket::Connection.new(1, {:standard_connection_class => FakeStandardConnection})
          conn.stub!(:send_data)
          conn.stub!(:close_connection_after_writing)
          conn.receive_data("GET / HTTP/1.1\r\n")
          conn.receive_data("User-Agent: EventMachine HttpClient\r\nHost: 127.0.0.1:12345\r\n\r\n")
          instance.received_data.should == @full_request
        end
      end
    end

  end

  context "when a websocket HTTP request comes in" do
    context "and the entire header is not received in one chunk" do
      before do
        @header_part_1 = [
          "GET / HTTP/1.1",
          "User-Agent: EventMachine HttpClient",
          "",
        ].join("\r\n")
        @header_part_2 = [
          "Connection: Upgrade",
          "Origin: 127.0.0.1",
          "Host: 127.0.0.1:12345",
          "Upgrade: WebSocket",
          "",
        ].join("\r\n")
        @header_part_2 = "#{@header_part_2}\r\n"
      end

      context "when only the first chunk has been received" do
        it "should not send the handshake back to the client yet" do
          conn = EventMachine::WebSocket::Connection.new(1, {})
          conn.should_not_receive(:send_data)
          conn.receive_data(@header_part_1)
        end
      end

      context "when both chunks have been received" do
        it "should send back the handshake" do
          conn = EventMachine::WebSocket::Connection.new(1, {})
          conn.should_receive(:send_data)
          conn.receive_data(@header_part_1)
          conn.receive_data(@header_part_2)

        end
      end
    end
  end

end