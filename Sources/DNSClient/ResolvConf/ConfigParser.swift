import NIO

fileprivate let nameserverPrefix = "nameserver"

/// A struct representing the contents of a resolv.conf file.
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
            let ipAddress = line.drop(while: { $0 == " " || $0 == "\t" })
            guard ipAddress.startIndex != line.startIndex else {
                // There should be at least one separator character
                continue nextLine
            }

            try nameservers.append(SocketAddress(ipAddress: String(ipAddress), port: 53))
        }

        self.nameservers = nameservers
    }
}
