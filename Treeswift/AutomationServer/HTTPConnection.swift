//
//  HTTPConnection.swift
//  Treeswift
//
//  Handles a single HTTP connection: reads request data, parses via CFHTTPMessage,
//  dispatches to Router, and writes the response back.
//

import CFNetwork
import Foundation
import Network

// Explicitly nonisolated — this class lives on connection-specific queues, not @MainActor.
// All @MainActor state access goes through the Router via async dispatch.
final class HTTPConnection: @unchecked Sendable {
	private let connection: NWConnection
	private let router: Router
	private var buffer = Data()
	private var handled = false
	// Self-retain: keeps this instance alive for the duration of the connection.
	private var selfRetain: HTTPConnection?

	init(connection: NWConnection, router: Router) {
		self.connection = connection
		self.router = router
	}

	func start(on queue: DispatchQueue) {
		selfRetain = self // Prevent deallocation until connection is closed
		connection.start(queue: queue)
		receive()
	}

	private func receive() {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
			guard let self, !self.handled else { return }

			if let data {
				buffer.append(data)
				if tryParseAndHandle() {
					return
				}
			}

			if isComplete || error != nil {
				connection.cancel()
			} else {
				receive()
			}
		}
	}

	// Returns true if a complete request was found and dispatched.
	private func tryParseAndHandle() -> Bool {
		// Find the header/body separator
		let separatorBytes = Data("\r\n\r\n".utf8)
		guard let separatorRange = buffer.range(of: separatorBytes) else {
			return false // Headers not complete yet
		}
		let headerEnd = separatorRange.upperBound

		// Parse the header section
		let headerData = buffer[..<separatorRange.lowerBound]
		guard let headerStr = String(data: headerData, encoding: .utf8) else { return false }

		let lines = headerStr.components(separatedBy: "\r\n")
		guard let requestLine = lines.first, !requestLine.isEmpty else { return false }

		let requestParts = requestLine.components(separatedBy: " ")
		guard requestParts.count >= 2 else { return false }

		let method = requestParts[0]
		let rawPath = requestParts[1]

		// Parse Content-Length
		var contentLength = 0
		var headers: [String: String] = [:]
		for line in lines.dropFirst() {
			let parts = line.components(separatedBy: ": ")
			if parts.count >= 2 {
				let key = parts[0].lowercased()
				let value = parts[1...].joined(separator: ": ")
				headers[key] = value
				if key == "content-length", let len = Int(value.trimmingCharacters(in: .whitespaces)) {
					contentLength = len
				}
			}
		}

		// Check if we have the full body
		let bodyStart = headerEnd
		let bodyEnd = bodyStart + contentLength
		guard buffer.count >= bodyEnd else { return false }

		handled = true

		// Parse URL components
		let urlComponents = URLComponents(string: rawPath)
		let path = urlComponents?.path ?? rawPath
		let pathComponents = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

		var queryItems: [String: String] = [:]
		for item in urlComponents?.queryItems ?? [] {
			queryItems[item.name] = item.value ?? ""
		}

		let bodyData: Data? = contentLength > 0 ? Data(buffer[bodyStart ..< bodyEnd]) : nil

		let request = Router.Request(
			method: method,
			path: path,
			pathComponents: pathComponents,
			queryItems: queryItems,
			body: bodyData
		)

		let requestMethod = method
		let requestPath = path
		Task.detached {
			let response = await self.router.handle(request: request)
			fputs("\(requestMethod) \(requestPath) -> \(response.statusCode)\n", stderr)
			self.send(response: response)
		}

		return true
	}

	private func send(response: Router.Response) {
		let statusText = switch response.statusCode {
		case 200: "OK"
		case 201: "Created"
		case 400: "Bad Request"
		case 404: "Not Found"
		case 409: "Conflict"
		case 501: "Not Implemented"
		default: "Internal Server Error"
		}

		let body = response.body ?? Data()
		let contentType = response.contentType ?? "application/json"
		let responseHeaders = [
			"HTTP/1.1 \(response.statusCode) \(statusText)",
			"Content-Type: \(contentType)",
			"Content-Length: \(body.count)",
			"Connection: close",
			"",
			""
		].joined(separator: "\r\n")

		var responseData = Data(responseHeaders.utf8)
		responseData.append(body)

		connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
			self?.connection.cancel()
			self?.selfRetain = nil // Release self-retain once connection is done
		})
	}
}
