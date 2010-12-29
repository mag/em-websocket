require 'spec/helper'

describe EventMachine::WebSocket do

  it "should automatically complete WebSocket handshake" do
    EM.run do
      MSG = "Hello World!"
      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('ws://127.0.0.1:12345/').get :timeout => 0
        http.errback { failed }
        http.callback { http.response_header.status.should == 101 }

        http.stream { |msg|
          msg.should == MSG
          EventMachine.stop
        }
      end

      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) do |ws|
        ws.onopen {
          ws.send MSG
        }
      end
    end
  end

  it "should split multiple messages into separate callbacks" do
    EM.run do
      messages = %w[1 2]
      received = []

      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('ws://127.0.0.1:12345/').get :timeout => 0
        http.errback { failed }
        http.stream {|msg|}
        http.callback {
          http.response_header.status.should == 101
          http.send messages[0]
          http.send messages[1]
        }
      end

      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) do |ws|
        ws.onopen {}
        ws.onclose {}
        ws.onmessage {|msg|
          msg.should == messages[received.size]
          received.push msg

          EventMachine.stop if received.size == messages.size
        }
      end
    end
  end

  it "should call onclose callback when client closes connection" do
    EM.run do
      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('ws://127.0.0.1:12345/').get :timeout => 0
        http.errback { failed }
        http.callback {
          http.response_header.status.should == 101
          http.close_connection
        }
        http.stream{|msg|}
      end

      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) do |ws|
        ws.onopen {}
        ws.onclose {
          ws.state.should == :closed
          EventMachine.stop
        }
      end
    end
  end

  context "when the client sends standard http traffic" do
    def fire_normal_http_request_in_future
      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('http://127.0.0.1:12345/').get :timeout => 0
        http.errback { failed }
        http.callback { http.response_header.status.should == 200; EventMachine.stop }
      end
    end

    def start_server(proxy)
      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345, :standard_connection_class => proxy) do |ws|
        ws.onopen { failed }
        ws.onclose { failed }
        ws.onerror { failed }
      end
    end


    # Fake standard connection that sends back a 200 OK and closes the connection
    class FakeMongrelConnection
      attr_writer :actual_connection
      attr_reader :received_data
      def post_init; end
      def receive_data(data)
        @received_data ||= ""
        @received_data << data
        if @received_data.split("\n").last.strip == ""
          @actual_connection.send_data "HTTP/1.1 200 OK\r\n\r\nFAKE RESPONSE"
          @actual_connection.close_connection_after_writing
        end
      end
    end

    it "should not fail" do
      EM.run do
        fire_normal_http_request_in_future
        start_server(FakeMongrelConnection)
      end
    end

    it "should forward all received data to a new instance of given standard connection class" do
      instance = nil
      EM.run do
        fire_normal_http_request_in_future
        instance = FakeMongrelConnection.new
        FakeMongrelConnection.stub(:new) {instance}
        start_server(FakeMongrelConnection)
      end
      lines = instance.received_data.split("\n")
      lines[0].strip.should == "GET / HTTP/1.1"
      lines[1].strip.should == "User-Agent: EventMachine HttpClient"
    end

    it "should call post_init on the standard connection object" do
      EM.run do
        fire_normal_http_request_in_future
        instance = FakeMongrelConnection.new
        FakeMongrelConnection.stub(:new) do
          instance.should_receive(:post_init)
          instance
        end
        start_server(FakeMongrelConnection)
      end
    end

    it "should give a copy of the actual connection to the standard connection so the latter can write data" do
      EM.run do
        EventMachine.add_timer(0.1) do
          http = EventMachine::HttpRequest.new('http://127.0.0.1:12345/').get :timeout => 0
          http.errback { failed }
          http.callback do
            http.response_header.status.should == 200
            http.response.should =~ %r|FAKE RESPONSE|
            EventMachine.stop
          end
        end
        instance = FakeMongrelConnection.new
        FakeMongrelConnection.stub(:new) { instance }
        start_server(FakeMongrelConnection)
      end

    end
  end

  it "should populate ws.request with appropriate headers" do
    EM.run do
      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('ws://127.0.0.1:12345/').get :timeout => 0
        http.errback { failed }
        http.callback {
          http.response_header.status.should == 101
          http.close_connection
        }
        http.stream { |msg| }
      end

      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) do |ws|
        ws.onopen {
          ws.request["User-Agent"].should == "EventMachine HttpClient"
          ws.request["Connection"].should == "Upgrade"
          ws.request["Upgrade"].should == "WebSocket"
          ws.request["Path"].should == "/"
          ws.request["Origin"].should == "127.0.0.1"
          ws.request["Host"].to_s.should == "ws://127.0.0.1:12345"
        }
        ws.onclose {
          ws.state.should == :closed
          EventMachine.stop
        }
      end
    end
  end

  it "should allow sending and retrieving query string args passed in on the connection request." do
    EM.run do
      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('ws://127.0.0.1:12345/').get(:query => {'foo' => 'bar', 'baz' => 'qux'}, :timeout => 0)
        http.errback { failed }
        http.callback {
          http.response_header.status.should == 101
          http.close_connection
        }
        http.stream { |msg| }
      end

      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) do |ws|
        ws.onopen {
          ws.request["Path"].should == "/?baz=qux&foo=bar"
          ws.request["Query"]["foo"].should == "bar"
          ws.request["Query"]["baz"].should == "qux"
        }
        ws.onclose {
          ws.state.should == :closed
          EventMachine.stop
        }
      end
    end
  end

  it "should ws.response['Query'] to empty hash when no query string params passed in connection URI" do
    EM.run do
      EventMachine.add_timer(0.1) do
        http = EventMachine::HttpRequest.new('ws://127.0.0.1:12345/').get(:timeout => 0)
        http.errback { failed }
        http.callback {
          http.response_header.status.should == 101
          http.close_connection
        }
        http.stream { |msg| }
      end

      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) do |ws|
        ws.onopen {
          ws.request["Path"].should == "/"
          ws.request["Query"].should == {}
        }
        ws.onclose {
          ws.state.should == :closed
          EventMachine.stop
        }
      end
    end
  end

  it "should raise an exception if frame sent before handshake complete" do
    EM.run {
      EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 12345) { |c|
        # We're not using a real client so the handshake will not be sent
        EM.add_timer(0.1) {
          lambda {
            c.send('early message')
          }.should raise_error('Cannot send data before onopen callback')
          EM.stop
        }
      }

      client = EM.connect('0.0.0.0', 12345, EM::Connection)
    }
  end
end
