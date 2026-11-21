import SwiftUI
import Foundation
import Darwin

struct DiscoveredRoku: Identifiable, Hashable {
    let id: String
    let host: String
    let name: String
    let modelNumber: String?
    let softwareVersion: String?
}

struct DiscoveryDiagnostics: Equatable {
    var probeSent = false
    var datagramsReceived = 0
    var validLocations = 0
    var deviceInfoLoaded = 0
    var error: String?

    var summary: String {
        if let error { return error }
        return "Probe: \(probeSent ? "sent" : "not sent") · Replies: \(datagramsReceived) · Roku locations: \(validLocations) · Devices loaded: \(deviceInfoLoaded)"
    }
}

struct DiscoveryResult {
    let devices: [DiscoveredRoku]
    let diagnostics: DiscoveryDiagnostics
}

final class DeviceInfoParser: NSObject, XMLParserDelegate {
    var values: [String:String] = [:]
    private var element = ""
    private var text = ""

    static func parse(_ data: Data) -> [String:String] {
        let delegate = DeviceInfoParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String:String] = [:]) {
        element = elementName
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[elementName] = value }
        element = ""
        text = ""
    }
}

enum RokuDiscovery {
    static func discover(timeout: TimeInterval = 4.0) async -> DiscoveryResult {
        let socketResult = await Task.detached(priority: .userInitiated) {
            discoverLocations(timeout: timeout)
        }.value

        var diagnostics = socketResult.diagnostics
        var devices: [DiscoveredRoku] = []

        for base in socketResult.locations {
            guard let host = base.host else { continue }
            do {
                var request = URLRequest(url: base.appendingPathComponent("query/device-info"))
                request.timeoutInterval = 4
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let info = DeviceInfoParser.parse(data)
                devices.append(DiscoveredRoku(
                    id: base.absoluteString,
                    host: host,
                    name: info["user-device-name"] ?? info["friendly-device-name"] ?? info["model-name"] ?? "Roku TV",
                    modelNumber: info["model-number"],
                    softwareVersion: info["software-version"]
                ))
                diagnostics.deviceInfoLoaded += 1
            } catch { continue }
        }

        let unique = Dictionary(grouping: devices, by: \.host).compactMap { $0.value.first }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return DiscoveryResult(devices: unique, diagnostics: diagnostics)
    }

    private static func discoverLocations(timeout: TimeInterval) -> (locations: [URL], diagnostics: DiscoveryDiagnostics) {
        var diagnostics = DiscoveryDiagnostics()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            diagnostics.error = "Could not create the SSDP UDP socket (errno \(errno))."
            return ([], diagnostics)
        }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bindResult = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0 else {
            diagnostics.error = "Could not bind the SSDP UDP socket (errno \(errno))."
            return ([], diagnostics)
        }

        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destination.sin_addr)

        let probe = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: roku:ecp\r\n\r\n"
        let sent = probe.withCString { bytes in
            withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, strlen(bytes), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else {
            diagnostics.error = "Could not send the SSDP probe (errno \(errno))."
            return ([], diagnostics)
        }
        diagnostics.probeSent = true

        let deadline = Date().addingTimeInterval(timeout)
        var locations = Set<URL>()
        var buffer = [UInt8](repeating: 0, count: 8192)

        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let timeoutMS = max(1, Int32(remaining * 1000))
            let ready = poll(&descriptor, 1, timeoutMS)
            if ready == 0 { break }
            if ready < 0 {
                if errno == EINTR { continue }
                diagnostics.error = "Waiting for SSDP replies failed (errno \(errno))."
                break
            }
            guard (descriptor.revents & Int16(POLLIN)) != 0 else { continue }

            let count = recvfrom(fd, &buffer, buffer.count - 1, 0, nil, nil)
            if count <= 0 { continue }
            diagnostics.datagramsReceived += 1
            guard let response = String(bytes: buffer[0..<count], encoding: .utf8) else { continue }

            for line in response.components(separatedBy: .newlines) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "location",
                      let url = URL(string: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                locations.insert(url)
            }
        }

        diagnostics.validLocations = locations.count
        return (Array(locations), diagnostics)
    }
}

struct DiscoveryView: View {
    @EnvironmentObject var model: TVModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Add a Roku TV").font(.title.bold())
                    Text("Search the local network, or enter an IP address manually.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            if model.isDiscovering {
                ProgressView("Looking for Roku TVs…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.discoveredRokus.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text("No Roku TVs found").font(.headline)
                    Text("Try again or enter the IP address manually.").foregroundStyle(.secondary)
                    Text(model.discoveryDiagnostics).font(.caption.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.discoveredRokus) { roku in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(roku.name).font(.headline)
                            Text([roku.host, roku.modelNumber].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isKnownHost(roku.host) {
                            Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Add") { Task { await model.addDiscovered(roku) } }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                Text(model.discoveryDiagnostics).font(.caption.monospaced()).foregroundStyle(.secondary)
            }

            HStack {
                Button("Search Again") { Task { await model.discoverRokus() } }.buttonStyle(.borderedProminent).disabled(model.isDiscovering)
                Button("Enter IP Manually") { dismiss(); model.openAddDevice() }
                Spacer()
                Text(model.message).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 650, minHeight: 470)
        .task { if model.discoveredRokus.isEmpty { await model.discoverRokus() } }
    }
}
