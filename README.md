# NioDNS

Async DNS resolution, with all the DNS features you need!

[Join our Discord](https://discord.gg/H6799jh) for any questions and friendly banter.

### Installation 💥

Add the package:

`.package(url: "https://github.com/orlandos-nl/DNSClient.git", from: "2.0.0"),`

And to your target:

`.product(name: "DNSClient", package: "DNSClient"),`

### Usage 🤯

Connect to your default DNS Server:
```swift
let client = try DNSClient.connect(on: loop).wait()
```

Connect to a specific DNS Server:
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

### Notes

The DNS Client doesn't retain itself during requests. This means that you cannot do the following:

```swift
DNSClient.connect(on: request.eventLoop).flatMap { client in
    // client.doQueryStuff()
}
```

The client will deallocate itself, resulting in a timeout. Make sure that the `client` is strongly referenced, either until all results are in or by setting it on a shared context. In Vapor, that can be the request's `storage` container. On other services, you could consider a global, ThreadSpecificVariable or a property on your class.

### Featured In 🛍

- [MongoKitten](https://github.com/openkitten/mongokitten)
- Any code that uses [MongoKitten](https://github.com/openkitten/mongokitten)
- Any code that uses [this client](https://github.com/OpenKitten/NioDNS)
- Maybe your code, too?
