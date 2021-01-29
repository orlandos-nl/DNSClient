# NioDNS

Async DNS resolution, with all the DNS features you need!

### Installation 💥

Add the package:

`.package(name: "DNSClient", url: "https://github.com/OpenKitten/NioDNS.git", from: "2.0.0"),`

(DNSClient name is needed because we renamed the repo on request by Apple on the Swift Forums)

And to your target:

`.product(name: "DNSClient", package: "DNSClient"),`

### Usage 🤯

Connect to a DNS Server
```swift
let googleDNS = SocketAddress(ipAddress: "8.8.8.8", port: 53)
let client = try DNSClient.connect(on: loop, config: [googleDNS]).wait()
```

Resolve SRV Records:

```swift
let records = try client.sendQuery(forHost: "example.com", type: .srv).wait()
```

Resolve TXT Records:

```swift
let records = try client.sendQuery(forHost: "example.com", type: .txt).wait()
```

Need I say more?

### Featured In 🛍

- [MongoKitten](https://github.com/openkitten/mongokitten)
- Any code that uses [MongoKitten](https://github.com/openkitten/mongokitten)
- Any code that uses [this client](https://github.com/OpenKitten/NioDNS)
- Maybe your code, too?
