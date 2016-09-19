//
//  Promise.swift
//  then
//
//  Created by Sacha Durand Saint Omer on 06/02/16.
//  Copyright © 2016 s4cha. All rights reserved.
//

import Foundation

enum PromiseState {
    case pending
    case fulfilled
    case rejected
}

public typealias EmptyPromise = Promise<Void>

public class Promise<T> {
    
    public typealias ResolveCallBack = (T) -> Void
    public typealias ProgressCallBack = (Float) -> Void
    public typealias RejectCallBack = (Error) -> Void
    public typealias PromiseCallBack = (@escaping ResolveCallBack, @escaping RejectCallBack) -> Void
    public typealias PromiseProgressCallBack =
        (@escaping ResolveCallBack, @escaping RejectCallBack, @escaping ProgressCallBack) -> Void
    private typealias SuccessBlock = (T) -> Void
    private var successBlocks = [SuccessBlock]()
    private typealias FailBlock = (Error) -> Void
    private var failBlocks = [FailBlock]()
    private typealias ProgressBlock = (Float) -> Void
    private var progressBlocks = [ProgressBlock]()
    private var finallyBlock:() -> Void = { t in }
    private var promiseCallBack: PromiseCallBack!
    private var promiseProgressCallBack: PromiseProgressCallBack?
    private var promiseStarted = false
    private var state: PromiseState = .pending
    private var value: T?
    private var progress: Float?
    private var error: Error?
    var initialPromiseStart:(() -> Void)?
    var initialPromiseStarted = false
    
    public init(callback:@escaping (@escaping ResolveCallBack, @escaping RejectCallBack) -> Void) {
        promiseCallBack = callback
    }
    
    public init(callback:@escaping (@escaping ResolveCallBack,
                                    @escaping RejectCallBack,
                                    @escaping ProgressCallBack) -> Void) {
        promiseProgressCallBack = callback
    }
    
    public func start() {
        promiseStarted = true
        if let p = promiseProgressCallBack {
            p(resolvePromise, rejectPromise, progressPromise)
        } else {
            promiseCallBack(resolvePromise, rejectPromise)
        }
    }
    
    //MARK: - then((T)-> X)
    
    @discardableResult public func then<X>(_ block:@escaping (T) -> X) -> Promise<X> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerThen(block)
    }

    @discardableResult public func registerThen<X>(_ block:@escaping (T) -> X) -> Promise<X> {
        let p = Promise<X> { resolve, reject, progress in
            switch self.state {
            case .fulfilled:
                if let v = self.value {
                    resolve(block(v))
                }
            case .rejected:
                if let e = self.error {
                    reject(e)
                }
            case .pending:
                self.successBlocks.append({ t in
                    resolve(block(t))
                })
                self.failBlocks.append(reject)
            }
            self.progressBlocks.append({ p in
                progress(p)
            })
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - then((T)->Promise<X>)
    
    @discardableResult public func then<X>(_ block:@escaping (T) -> Promise<X>) -> Promise<X> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerThen(block)
    }
    
    @discardableResult public
    func registerThen<X>(_ block: @escaping (T) -> Promise<X>) -> Promise<X> {
        let p = Promise<X> { resolve, reject in
            switch self.state {
            case .fulfilled:
                if let v = self.value {
                    self.registerNextPromise(block, result: v, resolve:resolve, reject:reject)
                }
            case .rejected:
                if let e = self.error {
                    reject(e)
                }
            case .pending:
                self.successBlocks.append({ t in
                    self.registerNextPromise(block, result: t, resolve:resolve, reject:reject)
                })
                self.failBlocks.append(reject)
            }
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - then(Promise<X>)
    
    @discardableResult public func then<X>(_ p: Promise<X>) -> Promise<X> {
        return then { _ in p }
    }
    
    @discardableResult public func registerThen<X>(_ p: Promise<X>) -> Promise<X> {
        return registerThen { _ in p }
    }
    
    //MARK: - Error
    
    @discardableResult public func onError(_ block: @escaping (Error) -> Void) -> Promise<Void> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerOnError(block)
    }
    
    @discardableResult public
    func registerOnError(_ block: @escaping (Error) -> Void) -> Promise<Void> {
        let p = Promise<Void> { resolve, reject, progress in
            switch self.state {
            case .fulfilled:
                reject(NSError(domain: "", code: 123, userInfo: nil))
            // No error so do nothing.
            case .rejected:
                if let e = self.error {
                    // Already failed so call error block
                    block(e)
                }
                resolve()
            case .pending:
                // if promise fails, resolve error promise
                self.failBlocks.append({ e in
                    block(e)
                    resolve()
                })
                self.successBlocks.append({ t in
                    resolve()
                })
            }
            self.progressBlocks.append({ p in
                progress(p)
            })
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - Finally
    
    @discardableResult public func finally<X>(_ block:@escaping () -> X) -> Promise<X> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerFinally(block)
    }
    
    @discardableResult public func registerFinally<X>(_ block:@escaping () -> X) -> Promise<X> {
        let p = Promise<X> { resolve, reject, progress in
            switch self.state {
            case .fulfilled:
                resolve(block())
            case .rejected:
                resolve(block())
            case .pending:
                self.failBlocks.append({ e in
                    resolve(block())
                })
                self.successBlocks.append({ t in
                    resolve(block())
                })
            }
            self.progressBlocks.append({ p in
                progress(p)
            })
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    //MARK: - Progress
    
    @discardableResult public func progress(_ block:@escaping (Float) -> Void) -> Promise<Void> {
        tryStartInitialPromise()
        startPromiseIfNeeded()
        return registerProgress(block)
    }
    
    @discardableResult public
    func registerProgress(_ block: @escaping (Float) -> Void) -> Promise<Void> {
        let p = Promise<Void> { resolve, reject, progress in
            switch self.state {
            case .fulfilled:
                resolve()
            case .rejected:
                if let e = self.error {
                    reject(e)
                }
            case .pending:()
                self.failBlocks.append(reject)
                self.successBlocks.append({ _ in
                    resolve()
                })
            }
            self.progressBlocks.append({ p in
                block(p)
                progress(p)
            })
        }
        p.start()
        passAlongFirstPromiseStartFunctionAndStateTo(p)
        return p
    }
    
    
    //MARK: - Helpers
    
    private func passAlongFirstPromiseStartFunctionAndStateTo<X>(_ p: Promise<X>) {
        // Pass along First promise start block
        if let startBlock = self.initialPromiseStart {
            p.initialPromiseStart = startBlock
        } else {
            p.initialPromiseStart = self.start
        }
        // Pass along initil promise start state.
        p.initialPromiseStarted = self.initialPromiseStarted
    }
    
    private func tryStartInitialPromise() {
        if !initialPromiseStarted {
            initialPromiseStart?()
            initialPromiseStarted = true
        }
    }
    
    private func startPromiseIfNeeded() {
        if !promiseStarted { start() }
    }
    
    private func registerNextPromise<X>(_ block: (T) -> Promise<X>,
                                        result: T,
                                        resolve: @escaping (X) -> Void,
                                        reject: @escaping RejectCallBack) {
        let nextPromise: Promise<X> = block(result)
        nextPromise.then { x in
            resolve(x)
        }.onError(reject)
    }
    
    private func resolvePromise(_ result: T) {
        state = .fulfilled
        value = result
        for sb in successBlocks {
            sb(result)
        }
        finallyBlock()
    }
    
    private func rejectPromise(_ e: Error) {
        state = .rejected
        error = e
        for fb in failBlocks {
            if let e = error {
                fb(e)
            }
        }
        finallyBlock()
    }
    
    private func progressPromise(_ p: Float) {
        progress = p
        for pb in progressBlocks {
            if let progress = progress {
                pb(progress)
            }
        }
    }
}
