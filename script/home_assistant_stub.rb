# A throwaway Home Assistant for developing the cameras panel without a real
# instance.
#
#   ruby script/home_assistant_stub.rb    # listens on 127.0.0.1:8123
#
# Then add a `home_assistant` connection with base_url http://127.0.0.1:8123 and
# any access token. It serves /api/states with four Reolink-shaped camera
# entities (one unavailable) and /api/camera_proxy/<entity> with a generated
# frame carrying a sweep that moves every second, so a refresh is visibly a
# refresh rather than a cached image.
#
# Frames are PNGs encoded by hand — zlib and CRC32 are stdlib, so this needs no
# image library.
require 'socket'
require 'json'
require 'zlib'

PORT = 8123

CAMERAS = {
  'camera.front_door' => { name: 'Front Door', state: 'idle', tint: [46, 84, 120] },
  'camera.driveway' => { name: 'Driveway', state: 'recording', tint: [58, 62, 84] },
  'camera.back_yard' => { name: 'Back Yard', state: 'idle', tint: [44, 82, 66] },
  'camera.side_gate' => { name: 'Side Gate', state: 'unavailable', tint: [70, 70, 70] }
}.freeze

OTHER_ENTITIES = [
  { entity_id: 'sensor.outside_temperature', state: '72', attributes: { friendly_name: 'Outside Temperature' } },
  { entity_id: 'light.porch', state: 'on', attributes: { friendly_name: 'Porch Light' } }
].freeze

WIDTH = 320
HEIGHT = 180

def png_chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

# A flat tint, a horizon line, and a vertical sweep whose position comes from the
# current second — enough to make a stale frame obvious at a glance.
def frame(tint)
  sweep = (Time.now.to_i % WIDTH)
  raw = +''.b

  HEIGHT.times do |y|
    raw << 0.chr
    horizon = (y - (HEIGHT * 0.62)).abs < 1
    WIDTH.times do |x|
      shade = 1.0 - (y.to_f / HEIGHT * 0.45)
      pixel = tint.map { |channel| (channel * shade).round.clamp(0, 255) }
      pixel = [210, 210, 210] if horizon
      pixel = pixel.map { |channel| (channel + 90).clamp(0, 255) } if (x - sweep).abs < 3
      raw << pixel[0].chr << pixel[1].chr << pixel[2].chr
    end
  end

  header = [WIDTH, HEIGHT].pack('NN') + [8, 2, 0, 0, 0].pack('C5')

  "\x89PNG\r\n\x1A\n".b +
    png_chunk('IHDR', header) +
    png_chunk('IDAT', Zlib::Deflate.deflate(raw)) +
    png_chunk('IEND', ''.b)
end

def states
  cameras = CAMERAS.map do |entity_id, camera|
    { entity_id: entity_id, state: camera[:state],
      last_updated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
      attributes: { friendly_name: camera[:name], supported_features: 2 } }
  end

  cameras + OTHER_ENTITIES
end

server = TCPServer.new('127.0.0.1', PORT)
puts "home assistant stub listening on #{PORT}"
$stdout.flush

loop do
  socket = server.accept
  request_line = socket.gets
  next socket.close if request_line.nil?

  _method, target, = request_line.split
  while (line = socket.gets) && line != "\r\n"
    # headers are irrelevant here
  end

  path = target.split('?', 1).first.to_s
  entity_id = path[%r{\A/api/camera_proxy/(.+)\z}, 1]

  if entity_id && CAMERAS.key?(entity_id)
    body = frame(CAMERAS[entity_id][:tint])
    type = 'image/png'
  elsif path == '/api/states'
    body = JSON.generate(states).b
    type = 'application/json'
  elsif path == '/api/'
    body = JSON.generate({ message: 'API running.' }).b
    type = 'application/json'
  else
    body = JSON.generate({ message: 'Entity not found.' }).b
    type = 'application/json'
  end

  socket.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\n" \
               "Cache-Control: no-store\r\nConnection: close\r\n\r\n")
  socket.write(body)
  socket.close
end
