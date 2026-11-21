import SwiftUI
import Foundation

@main struct WolffeTVApp: App {
    @StateObject private var model = TVModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).frame(minWidth: 620, minHeight: 680) }.windowStyle(.hiddenTitleBar)
        Settings { SetupView().environmentObject(model).frame(width: 430) }
    }
}

@MainActor final class TVModel: ObservableObject {
    @Published var tvName = UserDefaults.standard.string(forKey: "tvName") ?? "Living Room TV"
    @Published var tvIP = UserDefaults.standard.string(forKey: "tvIP") ?? ""
    @Published var online = false
    @Published var message = ""
    @Published var showingSetup = false
    @Published var showingRemote = false
    var configured: Bool { !tvIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    init() { showingSetup = !configured; if configured { Task { await checkStatus() } } }

    func save(name: String, ip: String) async -> Bool {
        let host = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validIPv4(host) else { message = "Enter a valid IPv4 address."; return false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tvName = n.isEmpty ? "Wolffe TV" : n; tvIP = host
        UserDefaults.standard.set(tvName, forKey: "tvName"); UserDefaults.standard.set(tvIP, forKey: "tvIP")
        await checkStatus(); if online { showingSetup = false; message = "✓ Connected to \(tvName)"; return true }
        message = "Saved, but the TV did not answer on the local network."; return false
    }
    func reset() { UserDefaults.standard.removeObject(forKey: "tvName"); UserDefaults.standard.removeObject(forKey: "tvIP"); tvName = "Living Room TV"; tvIP = ""; online = false; showingRemote = false; showingSetup = true; message = "" }
    func send(_ key: String, label: String) async {
        guard configured, let url = URL(string: "http://\(tvIP):8060/keypress/\(key)") else { showingSetup = true; return }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 4
        do { let (_, response) = try await URLSession.shared.data(for: r); guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else { throw URLError(.badServerResponse) }; online = true; message = "✓ \(label)" }
        catch { online = false; message = "Could not reach \(tvName)." }
    }
    func checkStatus() async {
        guard configured, let url = URL(string: "http://\(tvIP):8060/query/device-info") else { online = false; return }
        var r = URLRequest(url: url); r.timeoutInterval = 4
        do { let (_, response) = try await URLSession.shared.data(for: r); online = ((response as? HTTPURLResponse)?.statusCode == 200); message = online ? "✓ \(tvName) is reachable" : "TV did not return a successful response." }
        catch { online = false; message = "Could not reach \(tvName)." }
    }
    static func validIPv4(_ s: String) -> Bool { let p = s.split(separator: ".", omittingEmptySubsequences: false); return p.count == 4 && p.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false } }
}

struct ContentView: View {
    @EnvironmentObject var model: TVModel
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .bottom, endPoint: .top).ignoresSafeArea()
            ScrollView { VStack(spacing: 16) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text("LOCAL CONTROL · v4 ALPHA 2").font(.caption).tracking(3).foregroundStyle(.purple); Text(model.tvName.uppercased()).font(.system(size: 34, weight: .bold)).tracking(2) }; Spacer(); Label(model.online ? "TV ONLINE" : "TV OFFLINE", systemImage: "circle.fill").font(.caption).foregroundStyle(model.online ? .green : .red) }
                InputButton(title: "APPLE TV", subtitle: "HDMI 1 · ARC", icon: "apple.logo", tint: .purple) { await model.send("InputHDMI1", label: "Apple TV selected") }
                HStack(spacing: 16) {
                    InputButton(title: "UNUSED", subtitle: "HDMI 2", icon: "rectangle.on.rectangle", tint: .gray) { await model.send("InputHDMI2", label: "HDMI 2 selected") }
                    InputButton(title: "UNUSED", subtitle: "HDMI 3", icon: "rectangle.on.rectangle", tint: .gray) { await model.send("InputHDMI3", label: "HDMI 3 selected") }
                }
                InputButton(title: "WII", subtitle: "AV · COMPOSITE", icon: "gamecontroller.fill", tint: .indigo) { await model.send("InputAV1", label: "Wii selected") }
                Button { model.showingRemote = true } label: { Label("TV REMOTE", systemImage: "remote.fill").font(.headline).tracking(2).frame(maxWidth: .infinity).padding(14) }.buttonStyle(.borderedProminent).tint(Color(red: 0.28, green: 0.20, blue: 0.50))
                HStack { Button("Test Connection") { Task { await model.checkStatus() } }; Button("Setup") { model.showingSetup = true }; Button("Reset Setup", role: .destructive) { model.reset() } }.buttonStyle(.bordered)
                Text(model.message).foregroundStyle(.secondary).frame(minHeight: 24)
            }.padding(32) }
        }.foregroundStyle(.white)
         .sheet(isPresented: $model.showingSetup) { SetupView().environmentObject(model) }
         .sheet(isPresented: $model.showingRemote) { RemoteView().environmentObject(model) }
    }
}

struct InputButton: View {
    let title: String, subtitle: String, icon: String; let tint: Color; let action: () async -> Void
    var body: some View { Button { Task { await action() } } label: { HStack { Image(systemName: icon).font(.system(size: 32)); VStack(alignment: .leading) { Text(title).font(.title2.bold()).tracking(2); Text(subtitle).font(.caption).tracking(2).foregroundStyle(.white.opacity(0.72)) }; Spacer() }.padding(24).frame(maxWidth: .infinity, minHeight: 120).background(tint.gradient.opacity(0.82), in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain) }
}

struct RemoteView: View {
    @EnvironmentObject var model: TVModel; @Environment(\.dismiss) private var dismiss
    var body: some View { VStack(spacing: 16) {
        HStack { VStack(alignment: .leading) { Text("TV REMOTE").font(.title2.bold()).tracking(2); Text(model.tvName).foregroundStyle(.secondary) }; Spacer(); Button("Done") { dismiss() } }
        RButton("HOME", "house.fill") { await model.send("Home", label: "Home") }
        VStack(spacing: 8) {
            RButton("", "chevron.up") { await model.send("Up", label: "Up") }.frame(width: 86)
            HStack(spacing: 8) { RButton("", "chevron.left") { await model.send("Left", label: "Left") }; RButton("OK", nil, true) { await model.send("Select", label: "OK") }; RButton("", "chevron.right") { await model.send("Right", label: "Right") } }
            RButton("", "chevron.down") { await model.send("Down", label: "Down") }.frame(width: 86)
        }
        HStack(spacing: 10) { RButton("BACK", "arrow.uturn.backward") { await model.send("Back", label: "Back") }; RButton("PLAY", "playpause.fill") { await model.send("Play", label: "Play/Pause") }; RButton("OPTIONS", "asterisk") { await model.send("Info", label: "Options") } }
        HStack(spacing: 10) { RButton("VOL −", "speaker.minus.fill") { await model.send("VolumeDown", label: "Volume down") }; RButton("MUTE", "speaker.slash.fill") { await model.send("VolumeMute", label: "Mute") }; RButton("VOL +", "speaker.plus.fill") { await model.send("VolumeUp", label: "Volume up") } }
        HStack(spacing: 10) { RButton("REPLAY", "gobackward") { await model.send("InstantReplay", label: "Instant replay") }; RButton("POWER ON", "power") { await model.send("PowerOn", label: "Power on") }; RButton("POWER OFF", "power", false, true) { await model.send("PowerOff", label: "Power off") } }
        Text(model.message).foregroundStyle(.secondary).frame(minHeight: 22)
    }.padding(26).frame(width: 500) }
}

struct RButton: View {
    let title: String, icon: String?; var emphasized = false, destructive = false; let action: () async -> Void
    init(_ title: String, _ icon: String?, _ emphasized: Bool = false, _ destructive: Bool = false, action: @escaping () async -> Void) { self.title = title; self.icon = icon; self.emphasized = emphasized; self.destructive = destructive; self.action = action }
    var body: some View { Button { Task { await action() } } label: { VStack(spacing: 5) { if let icon { Image(systemName: icon).font(.title3) }; if !title.isEmpty { Text(title).font(.caption.bold()) } }.frame(maxWidth: .infinity, minHeight: 54) }.buttonStyle(.borderedProminent).tint(destructive ? .red : (emphasized ? .purple : .gray.opacity(0.55))) }
}

struct SetupView: View {
    @EnvironmentObject var model: TVModel
    @State private var name = ""
    @State private var ip = ""
    var body: some View { VStack(alignment: .leading, spacing: 18) { Text("Set Up Wolffe TV").font(.title.bold()); Text("Enter a friendly name and the local IPv4 address shown under Roku Settings › Network › About.").foregroundStyle(.secondary); TextField("TV name", text: $name); TextField("TV IP address", text: $ip); HStack { Spacer(); Button("Save and Test") { Task { _ = await model.save(name: name, ip: ip) } }.buttonStyle(.borderedProminent) }; Text(model.message).foregroundStyle(.secondary) }.padding(28).onAppear { name = model.tvName; ip = model.tvIP } }
}
