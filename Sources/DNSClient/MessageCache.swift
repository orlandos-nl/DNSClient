actor MessageCache {
    private var messageCache = [UInt16: SentQuery]()

    func queryForID(_ id: UInt16) -> SentQuery? {
        return messageCache[id]
    }

    func addQuery(_ query: SentQuery) {
        messageCache[query.message.header.id] = query
    }

    func removeQueryForID(_ id: UInt16) {
        messageCache[id] = nil
    }

    func failReset() {
        for query in messageCache.values {
            query.promise.fail(CancelError())
        }
        messageCache.removeAll()
    }
}