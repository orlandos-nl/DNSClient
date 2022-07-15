/// This actor provides a value that guarantees to respect the specified precondition.
///
/// At first call the value is generated using the provided generator, then the precondition is checked
/// and if it is not satisfied the value is regenerated up to the specified number of times.
/// The generation count is reset after each successful valid value generation.
/// If the specified number of times is exceeded, the actor will throw an error, either a generic error
/// if no error was thrown by the generator or the precondition, or the specific error that was thrown.
/// It is possible to specify a retry delay between each attempt.
actor GuaranteedAsyncValue<Value, Context> {
    private init(
        maxRetries: Int = 1,
        retryDelayNanoseconds: UInt64 = 0,
        generator: @escaping (Context) async throws -> Value,
        precondition: @escaping (Value, Context) async throws -> Bool,
        _ _: ()
    ) { 
        self.maxRetries = maxRetries
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.precondition = precondition
        self.generator = generator
        var streamContinuation: AsyncStream<(CheckedContinuation<Value, Error>, Context)>.Continuation! = nil
        self.continuationStream = AsyncStream<(CheckedContinuation<Value, Error>, Context)> { streamContinuation = $0 }
        self.streamContinuation = streamContinuation
    }

    convenience init(
        maxRetries: Int = 1,
        retryDelayNanoseconds: UInt64 = 0,
        generator: @escaping (Context) async throws -> Value,
        precondition: @escaping (Value, Context) async throws -> Bool
    ) {
        self.init(
            maxRetries: maxRetries,
            retryDelayNanoseconds: retryDelayNanoseconds,
            generator: generator,
            precondition: precondition, ()
        )

        Task {
            for await (continuation, context) in continuationStream {
                do {
                    continuation.resume(returning: try await self.getGuaranteedValue(context: context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The last valid value computed by the generator, nil if the generator has not yet been called.
    private var currentValue: Value?

    /// The generator is called when the value is requested, it should return a new value but can
    /// throw an error if it is unable to compute the value. Errors thrown cause a retry.
    private var generator: (Context) async throws -> Value

    /// The precondition is called with the value before it is used, it should return true if the
    /// value is valid, false or a specific error if it is not. If the precondition fails it
    /// causes a retry.
    private var precondition: (Value, Context) async throws -> Bool
    let streamContinuation: AsyncStream<(CheckedContinuation<Value, Error>, Context)>.Continuation
    private let continuationStream: AsyncStream<(CheckedContinuation<Value, Error>, Context)>
    let maxRetries: Int
    let retryDelayNanoseconds: UInt64

    struct UnableToGenerate: Error {}

    func getValue(context: Context) async throws -> Value {
        try await withCheckedThrowingContinuation {
            self.streamContinuation.yield(($0, context))
        }
    }

    private func getGuaranteedValue(context: Context) async throws -> Value {
        var lastError: Error
        var retryCount = 0
        repeat {
            // We initialize lastError to the default error value, it will be overwritten if anything
            // throws a more specific error before we get to the end of the loop.
            lastError = UnableToGenerate()
            if retryCount > 0 {
                // If we are about to retry, wait for the specified delay.
                try await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
            do {
                // Get the value from the generator or the cached value if it is available.
                let value = try await rawGenerateValue(context: context)
                if try await precondition(value, context) {
                    currentValue = value
                    return value
                } else {
                    // Failed, so the cached value is no longer valid.
                    currentValue = nil
                }
            } catch {
                // Failed, so the cached value is no longer valid.
                currentValue = nil
                if error is CancellationError {
                    // If the task was cancelled, we throw as soon as possible.
                    throw error
                } else {
                    lastError = error
                }
            }
            retryCount += 1
        } while retryCount <= maxRetries
        throw lastError
    }

    private func rawGenerateValue(context: Context) async throws -> Value {
        if let value = currentValue {
            return value
        } else {
            return try await generator(context)
        }
    }

}