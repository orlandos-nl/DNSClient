import NIO

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

let dnsClient = try NioDNS.connect(on: group, host: "8.8.8.8").wait()
print("Connected")
var buffer = dnsClient.channel.allocator.buffer(capacity: 4)
buffer.write(string: "Test")