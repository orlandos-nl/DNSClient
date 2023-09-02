# NioDNS

Async DNS resolution, with all the DNS features you need!

[Join our Discord](https://discord.gg/H6799jh) for any questions and friendly banter.

### Installation 💥

Add the package:

`.package(url: "https://github.com/orlandos-nl/DNSClient.git", from: "2.0.0"),`

And to your target:

`.product(name: "DNSClient", package: "DNSClient"),`

### Usage 🤯

Connect to your default DNS Server using UDP:

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

Resolve PTR Records:

```swift
let records = try client.ipv4InverseAddress("198.51.100.1").wait()

let records = try client.ipv6InverseAddress("2001:DB8::").wait()
```

Need I say more?

Note: You can replace `.wait()` function calls with `.get()` to get the result using async/await.

### iOS and TCP Support

On iOS 12+, you can connect using Network.Framework:

```swift
import NIOTransportServices
import DNSClient

let client = try DNSClient.connect(on: loop, host: "1.1.1.1").wait()
```

There is also another overload that implements TCP support:

```swift
let client = try DNSClient.connectTSTCP(on: loop, host: "1.1.1.1").wait()
```

TCP support is also available on Linux as `DNSClient.connectTCP(on: loop, host: ...)`

Note that NIOTS (TransportServices) needs their own EventLoop type, whereas NIO's `MultiThreadedEventLoopGroup` is used for the POSIX/Linux implementation.

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
