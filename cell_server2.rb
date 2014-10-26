require 'reel'
require 'pry'

class Handler
  include Celluloid

  def initialize(id, socket)
    @id = id
    @socket = socket
    @turn = 1
    loop
  end

  def loop
    begin
      t = Time.now
      sleep 0.5
      puts "#{t.strftime('%H:%M:%S')} #{t.usec}"
      @socket.write "loop #{@turn} for id:#{@id}"
      @turn += 1
      after(1){ loop }
    rescue => e
      puts e.message
      puts e.backtrace.join("\n")
    end
  end

  def handle(ws, msg)
    p "handle : #{msg}"
  end
end

class WebSocketServer < Reel::Server::HTTP

  def initialize(host="0.0.0.0", port=3000)
    @connections = {}
    @handlers = {}
    super(host, port, &method(:on_connection))
  end

  def on_connection(connection)
    connection.each_request do |request|
      if request.websocket?
        connection.detach
        ws = request.websocket
        ws.on_message { |msg|
          msg = JSON.load(msg)
          id = msg["id"].to_i
          puts "onmessage id:#{id}"
          async{
            h = @handlers[id]
            h.handle(ws, msg)
          }
        }
        ws.on_close {
          puts "closed"
          @connections.each do |id, cons|
            if cons.include?(ws)
              cons.delete(ws)
              @connections.delete(id)
            end
          end
        }

        query = qeury_to_hash(request.query_string)
        begin
          id = query["id"].to_i
          @connections[id] ||= []
          @connections[id] << ws unless @connections[id].index(ws)
          @handlers[id] = ::Handler.new(id, ws)
        rescue => e
          puts e.message
          puts e.backtrace.join("\n")
        end
        ws.read_every(0.1)

      else
        raise
      end
    end
  end

  private
  def qeury_to_hash(query_string)
    query = {}
    (query_string || '').split('&').each do |kv|
      key, value = kv.split('=')
      if key && value
        key, value = CGI.unescape(key), CGI.unescape(value)
        query[key] = value
      end
    end
    query
  end
end

WebSocketServer.run
