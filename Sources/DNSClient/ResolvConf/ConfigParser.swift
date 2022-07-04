import NIO

fileprivate let nameserverPrefix = "nameserver"

struct ResolvConf {
    let nameservers: [SocketAddress]

    init(from string: String) throws {
        let lines = string.split(separator: "\n")
        var nameservers = [SocketAddress]()

        nextLine: for var line in lines {
            guard line.starts(with: nameserverPrefix) else {
                continue nextLine
            }

            line.removeFirst(nameserverPrefix.count)
            let ipAddress = String(line.drop(while: { $0 == " " || $0 == "\t" }))
            try nameservers.append(SocketAddress(ipAddress: ipAddress, port: 53))
        }

        self.nameservers = nameservers
    }
}
