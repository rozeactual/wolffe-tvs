import Foundation
import Network
import Darwin

struct HostNetworkInfo: Equatable {
    var hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    var ipv4: [String] = []
    var ipv6: [String] = []
    var interfaces: [String] = []

    static func current() -> HostNetworkInfo {
        var result = HostNetworkInfo()
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return result }
        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let item = current.pointee
            cursor = item.ifa_next
            guard let address = item.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            let flags = Int32(item.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length: socklen_t = family == AF_INET
                ? socklen_t(MemoryLayout<sockaddr_in>.size)
                : socklen_t(MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let raw = String(cString: host)
            let value = raw.split(separator: "%", maxSplits: 1).first.map(String.init) ?? raw
            let name = String(cString: item.ifa_name)
            if family == AF_INET, !result.ipv4.contains(value) { result.ipv4.append(value) }
            if family == AF_INET6, !result.ipv6.contains(value) { result.ipv6.append(value) }
            if !result.interfaces.contains(name) { result.interfaces.append(name) }
        }
        return result
    }
}

struct WebInputSnapshot: Codable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let accent: String
}

struct WebDeviceSnapshot: Codable {
    let id: String
    let name: String
    let status: String
    let modelNumber: String?
    let inputs: [WebInputSnapshot]
}

struct WebDashboardSnapshot: Codable {
    let generatedAt: String
    let devices: [WebDeviceSnapshot]
}

final class WolffeWebServer {
    let port: UInt16
    var onState: ((String, Bool) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.wolffetv.webserver")
    private let snapshot: WebDashboardSnapshot

    init(port: UInt16, snapshot: WebDashboardSnapshot) {
        self.port = port
        self.snapshot = snapshot
    }

    func start() throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let listener = try NWListener(using: .tcp, on: endpointPort)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState?("Running", true)
            case .waiting(let error): self?.onState?("Waiting: \(error)", false)
            case .failed(let error): self?.onState?("Failed: \(error)", false)
            case .cancelled: self?.onState?("Stopped", false)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onState?("Stopped", false)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            self?.respond(to: connection, request: data ?? Data())
        }
    }

    private func respond(to connection: NWConnection, request: Data) {
        let text = String(data: request, encoding: .utf8) ?? ""
        let requestLine = text.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            send(status: "405 Method Not Allowed", type: "text/plain", body: "Read-only server", to: connection)
            return
        }

        switch String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "" {
        case "/":
            send(status: "200 OK", type: "text/html; charset=utf-8", body: Self.dashboardPage, to: connection)
        case "/api/status":
            send(status: "200 OK", type: "application/json; charset=utf-8", body: "{\"service\":\"Wolffe TV\",\"phase\":\"Alpha 4.0B\",\"status\":\"running\",\"port\":\(port),\"mode\":\"read-only\"}", to: connection)
        case "/api/devices":
            let data = (try? JSONEncoder().encode(snapshot)) ?? Data("{\"devices\":[]}".utf8)
            send(status: "200 OK", type: "application/json; charset=utf-8", bodyData: data, to: connection)
        default:
            send(status: "404 Not Found", type: "text/plain", body: "Not found", to: connection)
        }
    }

    private func send(status: String, type: String, body: String, to connection: NWConnection) {
        send(status: status, type: type, bodyData: Data(body.utf8), to: connection)
    }

    private func send(status: String, type: String, bodyData: Data, to connection: NWConnection) {
        var payload = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(bodyData.count)\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n".utf8)
        payload.append(bodyData)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static let dashboardPage = "<!doctype html>" +
        "<html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
        "<title>Wolffe TV</title><style>" +
        ":root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:linear-gradient(180deg,#171020,#070609);color:#f5f2f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}main{width:min(1050px,100%);margin:auto;padding:24px}header{padding:18px 4px 28px}h1{margin:0;color:#c78cff;letter-spacing:.12em}header p{color:#aaa}.device{background:#201827;border:1px solid #ffffff17;border-radius:24px;padding:22px;margin-bottom:20px;box-shadow:0 18px 50px #0005}.device-head{display:flex;gap:12px;align-items:center;justify-content:space-between}.badge{padding:6px 10px;border-radius:999px;background:#ffffff12;color:#ccc;font-size:.8rem}.online{color:#70e17a}.offline{color:#ff6b73}.inputs{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;margin-top:18px}.input{padding:18px;border-radius:18px;background:#6d3fa8aa;min-height:94px}.input strong{display:block;font-size:1.05rem}.input small{color:#ffffffb8}.empty{color:#aaa;padding-top:12px}.notice{margin-top:24px;padding:16px;border-radius:16px;background:#ffffff0b;color:#aaa}@media(max-width:520px){main{padding:16px}.device{padding:17px}.inputs{grid-template-columns:1fr 1fr}.input{padding:14px;min-height:82px}}" +
        "</style></head><body><main><header><h1>WOLFFE TV</h1><p>Read-only household dashboard</p></header><div id=\"app\">Loading saved TVs…</div><div class=\"notice\">Alpha 4.0B is view-only. TV controls and administration are intentionally unavailable.</div></main>" +
        "<script>const esc=s=>String(s??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',\"'\":'&#39;'}[c]));fetch('/api/devices',{cache:'no-store'}).then(r=>r.json()).then(data=>{const root=document.getElementById('app');if(!data.devices.length){root.innerHTML='<div class=\"device\">No TVs are saved on the host.</div>';return}root.innerHTML=data.devices.map(d=>'<section class=\"device\"><div class=\"device-head\"><div><h2>'+esc(d.name)+'</h2><small>'+esc(d.modelNumber||'Roku TV')+'</small></div><span class=\"badge '+esc(d.status)+'\">'+esc(d.status)+'</span></div>'+(d.inputs.length?'<div class=\"inputs\">'+d.inputs.map(i=>'<div class=\"input\"><strong>'+esc(i.name)+'</strong><small>'+esc(i.subtitle)+'</small></div>').join('')+'</div>':'<div class=\"empty\">No visible inputs are configured.</div>')+'</section>').join('')}).catch(()=>document.getElementById('app').innerHTML='<div class=\"device\">Could not load the host dashboard.</div>');</script></body></html>"
}
