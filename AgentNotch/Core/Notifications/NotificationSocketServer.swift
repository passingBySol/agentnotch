//
//  NotificationSocketServer.swift
//  AgentNotch
//
//  Unix domain socket server for receiving Claude Code notifications
//

import Foundation

/// Notification types from Claude Code hooks
enum ClaudeNotificationType: String, Codable {
    case permissionPrompt = "permission_prompt"
    case idlePrompt = "idle_prompt"
    case authSuccess = "auth_success"
    case elicitationDialog = "elicitation_dialog"
    case stop = "stop"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ClaudeNotificationType(rawValue: value) ?? .unknown
    }
}

/// Notification payload from Claude Code hook
struct ClaudeNotification: Codable {
    let sessionId: String?
    let cwd: String?
    let message: String?
    let notificationType: ClaudeNotificationType?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case message
        case notificationType = "notification_type"
        case toolName = "tool_name"
    }
}

/// Unix domain socket server for receiving notifications from Claude Code hooks
final class NotificationSocketServer {
    static let socketPath = "/tmp/agentnotch.sock"

    var onNotification: ((ClaudeNotification) -> Void)?
    var onError: ((String) -> Void)?

    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let acceptQueue = DispatchQueue(label: "com.agentnotch.notification.accept", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "com.agentnotch.notification.client", qos: .userInitiated, attributes: .concurrent)

    func start() throws {
        // Remove existing socket file if present
        unlink(Self.socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: "NotificationSocket", code: Int(errno),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create socket: \(String(cString: strerror(errno)))"])
        }

        // Set socket options
        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Bind to Unix socket path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy path to sun_path
        Self.socketPath.withCString { cString in
            withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
                let pathLen = min(strlen(cString), rawBuffer.count - 1)
                memcpy(rawBuffer.baseAddress!, cString, pathLen)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw NSError(domain: "NotificationSocket", code: Int(errno),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket: \(String(cString: strerror(errno)))"])
        }

        // Make socket world-writable
        chmod(Self.socketPath, 0o777)

        // Listen
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw NSError(domain: "NotificationSocket", code: Int(errno),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to listen: \(String(cString: strerror(errno)))"])
        }

        // Set non-blocking
        let flags = fcntl(serverSocket, F_GETFL)
        fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        isRunning = true
        debugLog("[NotificationSocket] Server started at \(Self.socketPath)")

        // Start accept loop
        startAcceptLoop()
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(Self.socketPath)
        debugLog("[NotificationSocket] Server stopped")
    }

    private func startAcceptLoop() {
        acceptQueue.async { [weak self] in
            guard let self = self else { return }

            while self.isRunning && self.serverSocket >= 0 {
                var clientAddr = sockaddr_un()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        accept(self.serverSocket, sockaddrPtr, &clientAddrLen)
                    }
                }

                if clientSocket >= 0 {
                    self.handleClient(clientSocket)
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    Thread.sleep(forTimeInterval: 0.1)
                } else if errno != EINTR {
                    let errorMsg = String(cString: strerror(errno))
                    debugLog("[NotificationSocket] Accept error: \(errorMsg)")
                    self.onError?("Accept error: \(errorMsg)")
                    break
                }
            }
        }
    }

    private func handleClient(_ clientSocket: Int32) {
        // Set client socket to non-blocking
        let flags = fcntl(clientSocket, F_GETFL)
        fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        clientQueue.async { [weak self] in
            defer { close(clientSocket) }

            var buffer = [UInt8](repeating: 0, count: 65536)
            var data = Data()
            var attempts = 0
            let maxAttempts = 10

            while attempts < maxAttempts {
                let bytesRead = read(clientSocket, &buffer, buffer.count)

                if bytesRead > 0 {
                    data.append(contentsOf: buffer[0..<bytesRead])
                    attempts = 0
                } else if bytesRead == 0 {
                    break
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    let sleepInterval = data.isEmpty ? 0.05 : 0.01
                    Thread.sleep(forTimeInterval: sleepInterval)
                    attempts += 1
                } else {
                    debugLog("[NotificationSocket] Read error: \(String(cString: strerror(errno)))")
                    break
                }
            }

            if !data.isEmpty {
                self?.processData(data)
            }
        }
    }

    private func processData(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let notification = try JSONDecoder().decode(ClaudeNotification.self, from: lineData)
                DispatchQueue.main.async { [weak self] in
                    self?.onNotification?(notification)
                }
            } catch {
                debugLog("[NotificationSocket] Parse error: \(error)")
                onError?("Failed to parse notification: \(error)")
            }
        }
    }
}
