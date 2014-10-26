require 'reel'
require 'celluloid/autostart'
require 'pry'

class SockHandler
  include Celluloid
  include Celluloid::Notifications

  def initialize(ins, ws)
    @instance = ins
    @socket = ws
    @socket.on_message{|msg| on_message(msg) }
    @socket.on_close{ on_close }
    async.run
  end

  def run
    loop do
      @socket.read
    end
  rescue EOFError
    puts "error"
    @instance.remove_con(@socket)
  end

  def on_message(message)
    puts "refrect: #{message}"
    begin
      @instance.send_to_all(message)
    rescue => e
      puts e.message
      puts e.backtrace.join("\n")
    end
  end

  def on_close
    puts "#on_close"
    @instance.remove_con(@socket)
  end
end

class Instance
  include Celluloid
  include Celluloid::Notifications

  attr_reader :id

  def initialize(id)
    @id = id
    @sock_handlers = {}
    @turn = 0
    @timer = every(1){ loop }
  end

  def add_con(ws)
    if @sock_handlers[ws].nil?
      @sock_handlers[ws] = SockHandler.new(self, ws)
    end
  end

  def loop
    begin
      t = Time.now
      str = "loop #{@turn} for id:#{@id} #{t.strftime('%H:%M:%S')} #{t.usec}"
      puts str
      send_to_all(str)
      @turn += 1
    rescue => e
      puts e.message
      puts e.backtrace.join("\n")
    end
  end

  def remove_con(ws)
    @sock_handlers.delete(ws)
    if @sock_handlers.empty?
      puts "terminate"
      @timer.cancel
      publish "remove_ins", @id
      terminate
    end
  end

  def send_to_all(msg)
    begin
      @sock_handlers.keys.map{|ws| ws.write(msg) }
    rescue => e
      puts e.message
      puts e.backtrace.join("\n")
    end
  end
end

class WebSocketServer < Reel::Server::HTTP
  include Celluloid::Notifications

  def initialize(host="0.0.0.0", port=3000)
    @instances = {}
    subscribe("remove_ins", :remove_ins)
    super(host, port, &method(:on_connection))
  end

  def on_connection(connection)
    connection.each_request do |request|
      if request.websocket?
        begin
          connection.detach
          ws = request.websocket
          query = qeury_to_hash(request.query_string)
          id = query["id"].to_i
          if @instances[id].nil?
            ins = Instance.new(id)
            @instances[id] = ins
          else
            ins = @instances[id]
          end
          ins.add_con(ws)
        rescue => e
          puts e.message
          puts e.backtrace.join("\n")
        end
      else
        raise
      end
    end
  end

  def remove_ins(topic, id)
    puts "#remove_ins #{id}"
    @instances.delete(id) unless @instances[id].nil?
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
