import Foundation
import Network

/// DLNA 投屏服务（对应安卓 dlna 包：SSDP 发现 + SOAP AVTransport 控制）
/// 用 NWConnection 组播搜索 urn:schemas-upnp-org:device:MediaRenderer:1，
/// 解析设备描述 XML，提供 play / stop / seek / setURL 控制。

struct CastDevice: Identifiable, Hashable {
    var id: String { location }
    var name: String = ""
    var location: String = ""     // 设备描述 XML 地址
    var controlURL: String = ""   // AVTransport 控制地址
    var host: String = ""
    var port: Int = 0
    var isTVBox = false           // 是否为 TVBox 私有协议
}

@MainActor
final class DLNAService: ObservableObject {
    static let shared = DLNAService()

    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var searching = false
    @Published var lastError: String? = nil

    private var browser: NWBrowser?

    // MARK: - SSDP 发现
    func search() async {
        searching = true
        devices = []
        // SSDP M-SEARCH 通过 UDP 组播 239.255.255.250:1900
        let responses = await ssdpDiscover()
        var found: [CastDevice] = []
        for resp in responses {
            guard let location = extractHeader("LOCATION", from: resp),
                  let url = URL(string: location) else { continue }
            var device = CastDevice(
                name: extractHeader("SERVER", from: resp) ?? "未命名设备",
                location: location,
                host: url.host ?? "",
                port: url.port ?? 80
            )
            if let desc = await NetworkService.getText(location),
               let control = parseControlURL(desc, base: url) {
                device.controlURL = control
                device.name = parseFriendlyName(desc) ?? device.name
                device.isTVBox = desc.localizedCaseInsensitiveContains("tvbox") ||
                                 desc.localizedCaseInsensitiveContains("avbox")
            }
            if !found.contains(where: { $0.location == device.location }) { found.append(device) }
        }
        devices = found
        searching = false
    }

    private func ssdpDiscover() async -> [String] {
        // 用 NWConnection 发 M-SEARCH 到组播地址，收集 ST 匹配响应
        var results: [String] = []
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "ssdp", attributes: .concurrent)
        let message = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
        \r
        """
        for host in ["239.255.255.250"] {
            guard let endpoint = NWEndpoint.hostPort(host: .init(host), port: 1900) else { continue }
            let conn = NWConnection(to: endpoint, using: .udp)
            group.enter()
            conn.stateUpdateHandler = { state in
                if case .ready = state {
                    conn.send(content: message.data(using: .utf8), completion: .contentProcessed { _ in
                        conn.receiveMessage { data, _, _, _ in
                            if let d = data, let s = String(data: d, encoding: .utf8) { results.append(s) }
                            group.leave()
                        }
                    })
                } else if case .failed = state { group.leave() }
            }
            conn.start(queue: queue)
        }
        await withCheckedContinuation { cont in
            group.notify(queue: .main) { cont.resume() }
        }
        return results
    }

    private func extractHeader(_ name: String, from response: String) -> String? {
        for line in response.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].caseInsensitiveCompare(name) == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func parseFriendlyName(_ xml: String) -> String? {
        xml.removingRegex("[\\s\\S]*<friendlyName>")
            .removingRegex("</friendlyName>[\\s\\S]*")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseControlURL(_ xml: String, base: URL) -> String? {
        let matched = xml.removingRegex("[\\s\\S]*<controlURL>")
            .removingRegex("</controlURL>[\\s\\S]*")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !matched.isEmpty else { return nil }
        if matched.hasPrefix("http") { return matched }
        let scheme = base.scheme ?? "http"
        let host = base.host ?? ""
        let port = base.port ?? 80
        let root = "\(scheme)://\(host):\(port)"
        return matched.hasPrefix("/") ? root + matched : root + "/" + matched
    }

    // MARK: - SOAP 控制
    /// 设置播放地址并播放（AVTransport:SetAVTransportURI + Play）
    func cast(url: String, title: String, to device: CastDevice) async -> Bool {
        let setBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(xmlEscape(url))</CurrentURI>
              <CurrentURIMetaData>&lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;\(xmlEscape(title))&lt;/dc:title&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        guard await soapAction(device.controlURL, action: "SetAVTransportURI", body: setBody) else { return false }
        let playBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID><Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """
        return await soapAction(device.controlURL, action: "Play", body: playBody)
    }

    func control(_ device: CastDevice, action: String) async -> Bool {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body><u:\(action) xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>\(action == "Seek" ? "<Unit>REL_TIME</Unit><Target>00:00:00</Target>" : "")
          </u:\(action)></s:Body>
        </s:Envelope>
        """
        return await soapAction(device.controlURL, action: action, body: body)
    }

    private func soapAction(_ url: String, action: String, body: String) async -> Bool {
        guard let u = URL(string: url) else { return false }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
