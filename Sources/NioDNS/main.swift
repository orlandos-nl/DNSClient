import NIO

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let dnsClient = try NioDNS.connect(on: group, host: "8.8.8.8").wait()
// 172.16.0.16
print("Connected")

//let result = try dnsClient.sendMessage(to: "google.com", type: .aaaa).wait()
//print(result)

//let results = try dnsClient.initiateAQuery(host: "google.com", port: 80).wait()
//for result in results {
//    print(result)
//}

//let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
//for result in results {
//    print(result)
//}

let answers = try dnsClient.getSRVRecords(from: "ok0-xkvc1.mongodb.net").wait()
print(answers)

//labels          63 octets or less
//names           255 octets or less
//TTL             positive values of a signed 32 bit number.
