//  MIT License
//
//  Copyright (c) 2023 Alkenso (Vladimir Vashurkin)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import SpellbookFoundation

import Foundation

public protocol HTTPClientProtocol {
    func data(for request: () throws -> URLRequest, completion: @escaping (Result<HTTPResult<Data>, Error>) -> Void)
    
    @available(macOS 12.0, iOS 15, tvOS 15.0, watchOS 8.0, *)
    func data(for request: () throws -> URLRequest, delegate: URLSessionTaskDelegate?) async throws -> HTTPResult<Data>
}

@available(macOS 12.0, iOS 15, tvOS 15.0, watchOS 8.0, *)
extension HTTPClientProtocol {
    public func data(for request: () throws -> URLRequest, completion: @escaping (Result<HTTPResult<Data>, any Error>) -> Void) {
        let request = Result(catching: request)
        Task {
            do {
                let result = try await data(for: request.get, delegate: nil)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

open class HTTPClient: HTTPClientProtocol {
    private var additionalHeaders = Synchronized<HTTPParameters<HTTPHeader>>(.unfair, .init())
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func updateHeaders(_ update: (inout HTTPParameters<HTTPHeader>) -> Void) {
        additionalHeaders.write(update)
    }
    
    public func data(
        for request: () throws -> URLRequest,
        completion: @escaping (Result<HTTPResult<Data>, Error>) -> Void
    ) {
        var urlRequest: URLRequest
        do {
            urlRequest = try request()
        } catch {
            completion(.failure(error))
            return
        }
        for additionalHeader in additionalHeaders.read().items {
            if urlRequest.value(forHTTPHeaderField: additionalHeader.key.rawValue) == nil {
                urlRequest.setValue(additionalHeader.value, forHTTPHeaderField: additionalHeader.key.rawValue)
            }
        }
        
        session.dataTask(with: urlRequest) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(URLError.badResponseType(response)))
                return
            }
            completion(.success(.init(value: data ?? Data(), response: response)))
        }.resume()
    }
    
    @available(macOS 12.0, iOS 15, tvOS 15.0, watchOS 8.0, *)
    public func data(
        for request: () throws -> URLRequest,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> HTTPResult<Data> {
        let (data, response) = try await session.data(for: request(), delegate: delegate)
        guard let response = response as? HTTPURLResponse else {
            throw URLError.badResponseType(response)
        }
        
        return .init(value: data, response: response)
    }
}
 
extension HTTPClientProtocol {
    public func data(for request: HTTPRequest, completion: @escaping (Result<HTTPResult<Data>, Error>) -> Void) {
        data(for: request.urlRequest, completion: completion)
    }
    
    func data(for request: URLRequest, completion: @escaping (Result<HTTPResult<Data>, Error>) -> Void) {
        data(for: { request }, completion: completion)
    }
    
    public func object<T>(
        _ type: T.Type = T.self,
        for request: HTTPRequest,
        decoder: ObjectDecoder<T>,
        completion: @escaping (Result<HTTPResult<T>, Error>) -> Void
    ) {
        object(type, for: request.urlRequest, decoder: decoder, completion: completion)
    }
    
    public func object<T>(
        _ type: T.Type = T.self,
        for request: () throws -> URLRequest,
        decoder: ObjectDecoder<T>,
        completion: @escaping (Result<HTTPResult<T>, Error>) -> Void
    ) {
        data(for: request) {
            completion($0.flatMap { dataResult in
                Self.decodeResponse(dataResult.value, decoder: decoder)
                    .map { .init(value: $0, response: dataResult.response) }
            })
        }
    }
    
    public func object<T>(
        _ type: T.Type = T.self,
        for request: URLRequest,
        decoder: ObjectDecoder<T>,
        completion: @escaping (Result<HTTPResult<T>, Error>) -> Void
    ) {
        data(for: request) {
            completion($0.flatMap { dataResult in
                Self.decodeResponse(dataResult.value, decoder: decoder)
                    .map { .init(value: $0, response: dataResult.response) }
            })
        }
    }
}

@available(macOS 12.0, iOS 15, tvOS 15.0, watchOS 8.0, *)
extension HTTPClientProtocol {
    public func data(
        for request: HTTPRequest,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> HTTPResult<Data> {
        try await data(for: request.urlRequest, delegate: delegate)
    }
    
    public func data(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> HTTPResult<Data> {
        try await data(for: { request }, delegate: delegate)
    }
    
    public func object<T>(
        for request: HTTPRequest,
        delegate: URLSessionTaskDelegate? = nil,
        decoder: ObjectDecoder<T>
    ) async throws -> HTTPResult<T> {
        try await object(for: request.urlRequest, delegate: delegate, decoder: decoder)
    }
    
    public func object<T>(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate? = nil,
        decoder: ObjectDecoder<T>
    ) async throws -> HTTPResult<T> {
        try await object(for: { request }, delegate: delegate, decoder: decoder)
    }
    
    public func object<T>(
        for request: () throws -> URLRequest,
        delegate: URLSessionTaskDelegate? = nil,
        decoder: ObjectDecoder<T>
    ) async throws -> HTTPResult<T> {
        let dataResult = try await data(for: request, delegate: delegate)
        let object = try Self.decodeResponse(dataResult.value, decoder: decoder).get()
        return .init(value: object, response: dataResult.response)
    }
}

extension HTTPClientProtocol {
    private static func decodeResponse<T>(
        _ data: Data,
        decoder: ObjectDecoder<T>
    ) -> Result<T, Error> {
        do {
            let object = try decoder.decode(T.self, data)
            return .success(object)
        } catch {
            return .failure(URLError.badResponse(error))
        }
    }
    
    private static func decodeResponse(
        _ data: Data,
        decoder: ObjectDecoder<EmptyCodable>
    ) -> Result<EmptyCodable, Error> {
        .success(.init())
    }
}

extension URLError {
    fileprivate static func badResponse(_ underlyingError: Error) -> URLError {
        URLError(.badServerResponse, userInfo: [NSUnderlyingErrorKey: underlyingError])
    }
    
    fileprivate static func badResponseType(_ response: URLResponse?) -> URLError {
        URLError(.badServerResponse, userInfo: [
            NSUnderlyingErrorKey: CommonError.cast(name: "HTTPResponse", response, to: HTTPURLResponse.self)
        ])
    }
}
