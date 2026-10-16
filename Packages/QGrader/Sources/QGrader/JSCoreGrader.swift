#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore

/// A thread that owns one JSContext. JavaScriptCore settles WebAssembly compilation
/// through the creating thread's run loop, so the loop is pumped between tasks.
final class JSWorker: @unchecked Sendable {
    private let cond = NSCondition()
    private var queue: [() -> Void] = []
    private var stopped = false
    private var thread: Thread?

    init(name: String) {
        let t = Thread { [self] in self.loop() }
        t.name = name
        t.stackSize = 16 * 1024 * 1024
        thread = t
        t.start()
    }

    func submit(_ work: @escaping () -> Void) {
        cond.lock()
        queue.append(work)
        cond.unlock()
    }

    func stop() {
        cond.lock()
        stopped = true
        cond.unlock()
    }

    private func loop() {
        while true {
            cond.lock()
            let batch = queue
            queue.removeAll()
            let done = stopped
            cond.unlock()
            if done { return }
            for work in batch { work() }
            if batch.isEmpty {
                // Run-loop sources/timers (wasm compile completion, promise jobs) fire here.
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
                Thread.sleep(forTimeInterval: 0.0005)
            }
        }
    }
}

private final class ErrorBox: @unchecked Sendable {
    var last: String?
    var log: [String] = []
}

/// Runs the bundled browser grader inside a JavaScriptCore JSContext via the
/// Android grader-host.js shim (the context supplies only the file-read hooks).
public final class JSCoreGrader: Grader, @unchecked Sendable {
    public let runtime = GraderRuntime.javaScriptCore

    private enum State {
        case idle
        case starting
        case ready
        case failed(GraderError)
    }

    private let bundle: GraderBundle
    private let timeout: TimeInterval
    private let worker = JSWorker(name: "qgrader.jscore")
    private let lock = NSLock()
    private var state = State.idle
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var context: JSContext?  // worker thread only
    private let errors = ErrorBox()

    public init(bundle: GraderBundle, startupTimeout: TimeInterval = 120) {
        self.bundle = bundle
        self.timeout = startupTimeout
    }

    public func shutdown() {
        worker.stop()
    }

    public func warmUp() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock()
            switch state {
            case .ready:
                lock.unlock()
                cont.resume()
            case .failed(let e):
                lock.unlock()
                cont.resume(throwing: e)
            case .starting:
                waiters.append(cont)
                lock.unlock()
            case .idle:
                state = .starting
                waiters.append(cont)
                lock.unlock()
                worker.submit { [self] in self.boot() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                    self.finish(.failure(.startupFailed("timed out after \(Int(self.timeout)) s")))
                }
            }
        }
    }

    private func finish(_ result: Result<Void, GraderError>) {
        lock.lock()
        guard case .starting = state else {
            lock.unlock()
            return
        }
        let pending = waiters
        waiters = []
        switch result {
        case .success: state = .ready
        case .failure(let e): state = .failed(e)
        }
        lock.unlock()
        for cont in pending {
            switch result {
            case .success: cont.resume()
            case .failure(let e): cont.resume(throwing: e)
            }
        }
    }

    // Runs on the worker thread.
    private func boot() {
        guard let ctx = JSContext() else {
            finish(.failure(.startupFailed("no JSContext")))
            return
        }
        let errors = self.errors
        ctx.exceptionHandler = { _, value in
            errors.last = value?.toString() ?? "unknown JS exception"
        }
        let bundle = self.bundle

        let readText: @convention(block) (String) -> JSValue = { path in
            let c = JSContext.current()!
            do {
                return JSValue(object: try bundle.readText(path), in: c)
            } catch {
                c.exception = JSValue(newErrorFromMessage: "read \(path): \(error)", in: c)
                return JSValue(undefinedIn: c)
            }
        }
        let readBinary: @convention(block) (String) -> JSValue = { path in
            let c = JSContext.current()!
            do {
                let data = try bundle.readData(path)
                if let buffer = JSCoreGrader.makeArrayBuffer(data, in: c) { return buffer }
                c.exception = JSValue(newErrorFromMessage: "ArrayBuffer for \(path) failed", in: c)
            } catch {
                c.exception = JSValue(newErrorFromMessage: "read \(path): \(error)", in: c)
            }
            return JSValue(undefinedIn: c)
        }
        let log: @convention(block) (String) -> Void = { message in
            errors.log.append(message)
        }
        let signal: @convention(block) (Bool, String) -> Void = { [weak self] ok, message in
            if ok {
                self?.finish(.success(()))
            } else {
                self?.finish(.failure(.startupFailed(message + " | log: " + (self?.errors.log.suffix(20).joined(separator: " ; ") ?? ""))))
            }
        }
        ctx.setObject(unsafeBitCast(readText, to: AnyObject.self), forKeyedSubscript: "__qmReadTextSync" as NSString)
        ctx.setObject(unsafeBitCast(readBinary, to: AnyObject.self), forKeyedSubscript: "__qmReadBinarySync" as NSString)
        ctx.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "__qmLogSync" as NSString)
        ctx.setObject(unsafeBitCast(signal, to: AnyObject.self), forKeyedSubscript: "__qmSignal" as NSString)

        let hasWasm = ctx.evaluateScript("typeof WebAssembly")?.toString() ?? "undefined"
        errors.log.append("typeof WebAssembly = \(hasWasm)")
        if hasWasm == "undefined" {
            finish(.failure(.startupFailed("WebAssembly is not available in this JSContext")))
            return
        }

        let preamble = """
        globalThis.__qmReadText = function (p) { return new Promise(function (res, rej) { try { res(__qmReadTextSync(p)); } catch (e) { rej(e); } }); };
        globalThis.__qmReadBinary = function (p) { return new Promise(function (res, rej) { try { res(__qmReadBinarySync(p)); } catch (e) { rej(e); } }); };
        globalThis.__qmLog = function (m) { __qmLogSync(String(m)); };
        """
        let host: String
        do {
            host = try GraderBundle.hostScript()
        } catch {
            finish(.failure(.startupFailed("\(error)")))
            return
        }
        ctx.evaluateScript(preamble)
        ctx.evaluateScript(host)
        if let e = errors.last {
            finish(.failure(.startupFailed("host script: \(e)")))
            return
        }
        ctx.evaluateScript("""
        __qmGraderReady.then(function () { __qmSignal(true, ""); },
                             function (e) { __qmSignal(false, String(e && e.name) + ": " + String(e && e.message) + " | " + String(e && e.stack) + " | typeof=" + typeof e + " json=" + (function () { try { return JSON.stringify(e); } catch (x) { return "?"; } })()); });
        """)
        if let e = errors.last {
            finish(.failure(.startupFailed("ready hook: \(e)")))
            return
        }
        context = ctx
    }

    public func grade(_ requests: [GraderRequest]) async throws -> [GraderResponse] {
        try await warmUp()
        let encoded = try JSONEncoder().encode(requests)
        let json = String(decoding: encoded, as: UTF8.self)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[GraderResponse], Error>) in
            worker.submit { [self] in
                guard let ctx = self.context, let fn = ctx.objectForKeyedSubscript("__qmGradeEnvelopes"), fn.isObject else {
                    cont.resume(throwing: GraderError.gradeFailed("grader not ready"))
                    return
                }
                self.errors.last = nil
                let result = fn.call(withArguments: [json])
                if let e = self.errors.last {
                    cont.resume(throwing: GraderError.gradeFailed(e))
                    return
                }
                guard let result, result.isString, let text = result.toString() else {
                    cont.resume(throwing: GraderError.malformedResponse("non-string result"))
                    return
                }
                do {
                    cont.resume(returning: try JSONDecoder().decode([GraderResponse].self, from: Data(text.utf8)))
                } catch {
                    cont.resume(throwing: GraderError.malformedResponse("\(error)"))
                }
            }
        }
    }

    /// Diagnostics collected during startup (`typeof WebAssembly`, host log lines).
    public var diagnostics: [String] { errors.log }

    private static func makeArrayBuffer(_ data: Data, in ctx: JSContext) -> JSValue? {
        let count = data.count
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 16)
        data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: count)
        var exception: JSValueRef?
        guard let ref = JSObjectMakeArrayBufferWithBytesNoCopy(
            ctx.jsGlobalContextRef,
            bytes,
            count,
            { pointer, _ in pointer?.deallocate() },
            nil,
            &exception
        ) else {
            bytes.deallocate()
            return nil
        }
        return JSValue(jsValueRef: ref, in: ctx)
    }
}

#endif
