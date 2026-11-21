import SwiftUI
import Foundation

@main
struct WolffeTVApp: App {
    @StateObject private var model = TVModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(minWidth: 620, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SetupView().environmentObject(model).frame(width: 430)
        }
    }
}

@MainActor
final class TVModel: ObservableObject {
    @Published var tvName = UserDefaults.standard.string(forKey: "tvName") ?? "Living Room TV"
    @Published var tvIP = UserDefaults.standard.string(forKey: "tvIP") ?? ""
    @Published var online = false
    @Published var message = ""
    @Published var showingSetup = false

    var configured: Bool { !tvIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {
        showingSetup = !configured
        if configured { Task { await checkStatus() } }
    }

    func save(name: String, ip: String) async -> Bool {
        guard Self.validIPv4(ip) else {
            message = "Enter a valid IPv4 address."
            return false
        }
        tvName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Wolffe TV" : name
        tvIP = ip
        UserDefaults.standard.set(tvName, forKey: "tvName")
        UserDefaults.standard.set(tvIP, forKey: "tvIP")
        await checkStatus()
        if online { showingSetup = false; return true }
        message = "Saved, but the TV did not answer on the local network."
        return false
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: "tvName")
        UserDefaults.standard.removeObject(forKey: "tvIP")
        tvName = "Living Room TV"; tvIP = ""; online = false; showingSetup = true
    }

    func send(_ key: String, label: String) async {
        guard configured, let url = URL(string: "http://\(tvIP):8060/keypress/\(key)") else { showingSetup = true; return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) { online = true; message = "✓ \(label) selected" }
            else { throw URLError(.badServerResponse) }
        } catch { online = false; message = "Could not reach \(tvName)." }
    }

    func checkStatus() async {
        guard configured, let url = URL(string: "http://\(tvIP):8060/query/device-info") else { online = false; return }
        var request = URLRequest(url: url); request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            online = ((response as? HTTPURLResponse)?.statusCode == 200)
        } catch { online = false }
    }

    static func validIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: TVModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .bottom, endPoint: .top).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LOCAL CONTROL · v4").font(.caption).tracking(3).foregroundStyle(.purple)
                            Text(model.tvName.uppercased()).font(.system(size: 34, weight: .bold)).tracking(2)
                        }
                        Spacer()
                        Label(model.online ? "TV ONLINE" : "TV OFFLINE", systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(model.online ? .green : .red)
                    }
                    InputButton(title: "APPLE TV", subtitle: "HDMI 1 · ARC", icon: "apple.logo", tint: .purple) { await model.send("InputHDMI1", label: "Apple TV") }
                    HStack(spacing: 16) {
                        InputButton(title: "UNUSED", subtitle: "HDMI 2", icon: "rectangle.on.rectangle", tint: .gray) { await model.send("InputHDMI2", label: "HDMI 2") }
                        InputButton(title: "UNUSED", subtitle: "HDMI 3", icon: "rectangle.on.rectangle", tint: .gray) { await model.send("InputHDMI3", label: "HDMI 3") }
                    }
                    InputButton(title: "WII", subtitle: "AV · COMPOSITE", icon: "gamecontroller.fill", tint: .indigo) { await model.send("InputAV1", label: "Wii") }
                    HStack {
                        Button("Test Connection") { Task { await model.checkStatus() } }
                        Button("Setup") { model.showingSetup = true }
                        Button("Reset Setup", role: .destructive) { model.reset() }
                    }.buttonStyle(.bordered)
                    Text(model.message).foregroundStyle(.secondary).frame(minHeight: 24)
                }.padding(32)
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $model.showingSetup) { SetupView().environmentObject(model) }
    }
}

struct InputButton: View {
    let title: String; let subtitle: String; let icon: String; let tint: Color; let action: () async -> Void
    var body: some View {
        Button { Task { await action() } } label: {
            HStack { Image(systemName: icon).font(.system(size: 32)); VStack(alignment: .leading) { Text(title).font(.title2.bold()).tracking(2); Text(subtitle).font(.caption).tracking(2).foregroundStyle(.white.opacity(0.72)) }; Spacer() }
                .padding(24).frame(maxWidth: .infinity, minHeight: 120).background(tint.gradient.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }
}

struct SetupView: View {
    @EnvironmentObject var model: TVModel
    @State private var name = ""
    @State private var ip = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set Up Wolffe TV").font(.title.bold())
            Text("Enter a friendly name and the local IPv4 address shown under Roku Settings › Network › About.").foregroundStyle(.secondary)
            TextField("TV name", text: $name)
            TextField("TV IP address", text: $ip)
            HStack { Spacer(); Button("Save and Test") { Task { _ = await model.save(name: name, ip: ip) } }.buttonStyle(.borderedProminent) }
            Text(model.message).foregroundStyle(.secondary)
        }.padding(28).onAppear { name = model.tvName; ip = model.tvIP }
    }
}
