import SwiftUI
import Foundation
import AppKit

struct RokuDevice: Codable, Identifiable, Hashable {
    var id: UUID
    var customName: String
    var host: String
    var discoveredName: String?
    var modelNumber: String?
    var softwareVersion: String?
    var inputs: [RokuInput]?

    init(id: UUID = UUID(), customName: String, host: String, discoveredName: String? = nil, modelNumber: String? = nil, softwareVersion: String? = nil, inputs: [RokuInput]? = nil) {
        self.id = id
        self.customName = customName
        self.host = host
        self.discoveredName = discoveredName
        self.modelNumber = modelNumber
        self.softwareVersion = softwareVersion
        self.inputs = inputs
    }
}

struct WolffeTVState: Codable {
    var schemaVersion = 1
    var selectedDeviceID: UUID?
    var devices: [RokuDevice] = []
}

@main
struct WolffeTVApp: App {
    @StateObject private var model = TVModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 620, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            DeviceEditorView(mode: .editSelected)
                .environmentObject(model)
                .frame(width: 460)
        }
    }
}

@MainActor
final class TVModel: ObservableObject {
    @Published private(set) var state: WolffeTVState
    @Published var online = false
    @Published var message = ""
    @Published var showingDeviceEditor = false
    @Published var editorMode: DeviceEditorMode = .add
    @Published var showingRemote = false
    @Published var showingInputManager = false
    @Published var showingDiscovery = false
    @Published var showingServerSettings = false
    @Published var isDiscovering = false
    @Published var discoveredRokus: [DiscoveredRoku] = []
    @Published var discoveryDiagnostics = "Discovery has not run yet."
    @Published var showingOnboarding: Bool
    @Published var onboardingStep = 0
    @Published var webServerRunning = false
    @Published var webServerStatus = "Stopped"
    @Published var webServerPort = 8765
    @Published var webHostID = ""
    @Published var webAccessCode = ""
    @Published var webMaxClients = 1
    @Published var hostNetworkInfo = HostNetworkInfo.current()
    private var webServer:WolffeWebServer?

    private let stateKey = "wolffeTVState.v1"
    private let defaults = UserDefaults.standard
    private let onboardingKey = "wolffeTV.hasCompletedOnboarding.v1"
    private let webPortKey="wolffeTV.webServer.port.v1",webHostIDKey="wolffeTV.webServer.hostID.v1",webAccessCodeKey="wolffeTV.webServer.accessCode.v1",webMaxClientsKey="wolffeTV.webServer.maxClients.v1"

    var devices: [RokuDevice] { state.devices }
    var selectedDevice: RokuDevice? {
        guard let id = state.selectedDeviceID else { return state.devices.first }
        return state.devices.first(where: { $0.id == id }) ?? state.devices.first
    }
    var configured: Bool { selectedDevice != nil }
    var selectedInputs:[RokuInput] { selectedDevice?.inputs ?? [] }

    init() {
        state = WolffeTVState()
        showingOnboarding = !UserDefaults.standard.bool(forKey: "wolffeTV.hasCompletedOnboarding.v1")
        loadOrMigrateState()
        loadWebServerPreferences()
        if !showingOnboarding {
            if configured { Task { await checkStatus() } }
            else { editorMode = .add; showingDeviceEditor = true }
        }
    }

    func loadWebServerPreferences(){let p=defaults.integer(forKey:webPortKey);webServerPort=p==0 ? 8765:p;webHostID=defaults.string(forKey:webHostIDKey) ?? "WTV-\(UUID().uuidString.prefix(8).uppercased())";webAccessCode=defaults.string(forKey:webAccessCodeKey) ?? String(format:"%06d",Int.random(in:0...999999));let m=defaults.integer(forKey:webMaxClientsKey);webMaxClients=m==0 ? 1:max(1,m);defaults.set(webHostID,forKey:webHostIDKey);defaults.set(webAccessCode,forKey:webAccessCodeKey);saveWebServerPreferences();refreshHostNetworkInfo()}
    func refreshHostNetworkInfo(){hostNetworkInfo=HostNetworkInfo.current()}
    func saveWebServerPreferences(){webServerPort=min(65535,max(1024,webServerPort));webMaxClients=max(1,webMaxClients);defaults.set(webServerPort,forKey:webPortKey);defaults.set(webMaxClients,forKey:webMaxClientsKey)}
    func startWebServer(){guard !webServerRunning,let p=UInt16(exactly:webServerPort)else{return};do{let w=WolffeWebServer(port:p);w.onState={[weak self]a,b in Task{@MainActor in self?.webServerStatus=a;self?.webServerRunning=b}};try w.start();webServer=w;webServerStatus="Starting…"}catch{webServerStatus="Failed: \(error.localizedDescription)"}}
    func stopWebServer(){webServer?.stop();webServer=nil;webServerRunning=false;webServerStatus="Stopped"}
    func regenerateAccessCode(){webAccessCode=String(format:"%06d",Int.random(in:0...999999));defaults.set(webAccessCode,forKey:webAccessCodeKey)}
    var preferredWebURL:String?{hostNetworkInfo.ipv4.first.map{"http://\($0):\(webServerPort)"}}
    func beginOnboardingNetworkCheck() async {
        onboardingStep = 1
        await discoverRokus()
        onboardingStep = 2
    }

    func completeOnboarding() {
        defaults.set(true, forKey: onboardingKey)
        showingOnboarding = false
        if configured { Task { await checkStatus() } }
        else { editorMode = .add; showingDeviceEditor = true }
    }

    func completeOnboardingWithManualEntry() {
        defaults.set(true, forKey: onboardingKey)
        showingOnboarding = false
        openAddDevice()
    }

    func openLocalNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") else { return }
        NSWorkspace.shared.open(url)
    }

    func selectDevice(_ id: UUID) {
        guard state.devices.contains(where: { $0.id == id }) else { return }
        state.selectedDeviceID = id
        online = false
        message = ""
        persist()
        Task { await checkStatus() }
    }

    func openAddDevice() {
        editorMode = .add
        showingDeviceEditor = true
    }

    func openEditSelected() {
        guard selectedDevice != nil else { openAddDevice(); return }
        editorMode = .editSelected
        showingDeviceEditor = true
    }

    func saveDevice(id: UUID?, name: String, host: String) async -> Bool {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validIPv4(cleanHost) else {
            message = "Enter a valid IPv4 address."
            return false
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "Roku TV" : cleanName

        if let id, let index = state.devices.firstIndex(where: { $0.id == id }) {
            state.devices[index].customName = finalName
            state.devices[index].host = cleanHost
            state.selectedDeviceID = id
        } else {
            let device = RokuDevice(customName: finalName, host: cleanHost)
            state.devices.append(device)
            state.selectedDeviceID = device.id
        }

        persist()
        await checkStatus()
        if online {
            showingDeviceEditor = false
            message = "✓ Connected to \(selectedDevice?.customName ?? finalName)"
            return true
        }
        message = "Saved, but the TV did not answer on the local network."
        return false
    }

    func deleteSelectedDevice() {
        guard let selected = selectedDevice else { return }
        state.devices.removeAll(where: { $0.id == selected.id })
        state.selectedDeviceID = state.devices.first?.id
        online = false
        persist()
        showingDeviceEditor = false
        if configured {
            Task { await checkStatus() }
        } else {
            editorMode = .add
            showingDeviceEditor = true
        }
    }

    func resetAllDevices() {
        state = WolffeTVState()
        online = false
        message = ""
        showingRemote = false
        persist()
        editorMode = .add
        showingDeviceEditor = true
    }

    func isKnownHost(_ host:String)->Bool { state.devices.contains{$0.host==host} }
    func discoverRokus() async { isDiscovering = true; message = ""; let result = await RokuDiscovery.discover(); discoveredRokus = result.devices; discoveryDiagnostics = result.diagnostics.summary; isDiscovering = false; message = discoveredRokus.isEmpty ? "No Roku TVs discovered." : "✓ Found \(discoveredRokus.count) Roku TV(s)" }
    func addDiscovered(_ r:DiscoveredRoku) async { guard !isKnownHost(r.host) else{message="That TV is already added.";return};let d=RokuDevice(customName:r.name,host:r.host,discoveredName:r.name,modelNumber:r.modelNumber,softwareVersion:r.softwareVersion);state.devices.append(d);state.selectedDeviceID=d.id;persist();await checkStatus();await refreshInputs();message="✓ Added \(r.name)" }
    func replaceInputs(_ v:[RokuInput]) { guard let id=selectedDevice?.id,let i=state.devices.firstIndex(where:{$0.id==id}) else{return};state.devices[i].inputs=v;persist() }
    func refreshInputs() async { guard let d=selectedDevice,let u=URL(string:"http://\(d.host):8060/query/apps") else{return};do{var r=URLRequest(url:u);r.timeoutInterval=5;let(data,res)=try await URLSession.shared.data(for:r);guard(res as? HTTPURLResponse)?.statusCode==200 else{throw URLError(.badServerResponse)};let fresh=InputParser.parse(data);guard !fresh.isEmpty else{message="No physical inputs detected.";return};let old=Dictionary(uniqueKeysWithValues:selectedInputs.map{($0.ecpID,$0)});let merged=fresh.map{f->RokuInput in var x=f;if let o=old[f.ecpID]{x.customName=o.customName;x.isVisible=o.isVisible;x.sortOrder=o.sortOrder;x.iconName=o.iconName;x.accentName=o.accentName};return x};replaceInputs(merged);message="✓ Detected \(merged.count) inputs for \(d.customName)"}catch{message="Could not refresh inputs from \(d.customName)."} }
    func activate(_ input:RokuInput) async { guard let k=input.key else{message="Input is not mapped.";return};await send(k,label:"\(input.displayName) selected") }
    func send(_ key: String, label: String) async {
        guard let device = selectedDevice,
              let url = URL(string: "http://\(device.host):8060/keypress/\(key)") else {
            openAddDevice()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
                throw URLError(.badServerResponse)
            }
            online = true
            message = "✓ \(label)"
        } catch {
            online = false
            message = "Could not reach \(device.customName)."
        }
    }

    func checkStatus() async {
        guard let device = selectedDevice,
              let url = URL(string: "http://\(device.host):8060/query/device-info") else {
            online = false
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            online = ((response as? HTTPURLResponse)?.statusCode == 200)
            message = online ? "✓ \(device.customName) is reachable" : "TV did not return a successful response."
        } catch {
            online = false
            message = "Could not reach \(device.customName)."
        }
    }

    private func loadOrMigrateState() {
        if let data = defaults.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(WolffeTVState.self, from: data) {
            state = decoded
            normalizeSelection()
            return
        }

        let legacyName = defaults.string(forKey: "tvName")
        let legacyIP = defaults.string(forKey: "tvIP")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let legacyIP, !legacyIP.isEmpty, Self.validIPv4(legacyIP) {
            let migrated = RokuDevice(customName: legacyName?.isEmpty == false ? legacyName! : "Living Room TV", host: legacyIP)
            state = WolffeTVState(selectedDeviceID: migrated.id, devices: [migrated])
            persist()
            message = "Previous TV settings migrated to the multi-device format."
        }
    }

    private func normalizeSelection() {
        if let id = state.selectedDeviceID, state.devices.contains(where: { $0.id == id }) { return }
        state.selectedDeviceID = state.devices.first?.id
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    static func validIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            Int($0).map { (0...255).contains($0) } ?? false
        }
    }
}

enum DeviceEditorMode: String, Identifiable {
    case add
    case editSelected
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var model: TVModel

    var body: some View {
        Group {
            if model.showingOnboarding {
                OnboardingView().environmentObject(model)
            } else if model.showingRemote {
                RemoteView().environmentObject(model)
            } else {
                dashboard
            }
        }
        .sheet(isPresented: $model.showingDeviceEditor) {
            DeviceEditorView(mode: model.editorMode).environmentObject(model)
        }
        .sheet(isPresented: $model.showingInputManager) { InputManagerView().environmentObject(model) }
        .sheet(isPresented: $model.showingDiscovery) { DiscoveryView().environmentObject(model) }
        .sheet(isPresented: $model.showingServerSettings) { WebServerSettingsView().environmentObject(model) }
    }

    private var dashboard: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .bottom, endPoint: .top)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if model.selectedInputs.isEmpty { VStack(spacing:12){Text("Inputs have not been detected for this TV.").foregroundStyle(.secondary);Button("Detect Inputs"){Task{await model.refreshInputs()}}.buttonStyle(.borderedProminent)}.frame(maxWidth:.infinity,minHeight:180).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:22)) } else { InputGrid(inputs:model.selectedInputs).environmentObject(model) }

                    Button { model.showingRemote = true } label: {
                        Label("TV REMOTE", systemImage: "remote.fill")
                            .font(.headline).tracking(2).frame(maxWidth: .infinity).padding(14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.28, green: 0.20, blue: 0.50))
                    .disabled(!model.configured)

                    HStack {
                        Button("Test Connection") { Task { await model.checkStatus() } }.disabled(!model.configured)
                        Button("Edit TV") { model.openEditSelected() }.disabled(!model.configured)
                        Button("Customize Inputs") { model.showingInputManager=true }.disabled(!model.configured)
                        Button("Add TV") { model.showingDiscovery = true }
                          Button("Web Server") { model.showingServerSettings=true }
                    }
                    .buttonStyle(.bordered)

                    Text(model.message).foregroundStyle(.secondary).frame(minHeight: 24)
                }
                .padding(32)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("LOCAL CONTROL · v4 ALPHA 4.0A.2").font(.caption).tracking(3).foregroundStyle(.purple)
                if model.devices.count > 1 {
                    Picker("TV", selection: Binding(
                        get: { model.selectedDevice?.id ?? model.devices.first?.id ?? UUID() },
                        set: { model.selectDevice($0) }
                    )) {
                        ForEach(model.devices) { device in
                            Text(device.customName).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.title2.bold())
                } else {
                    Text((model.selectedDevice?.customName ?? "NO TV CONFIGURED").uppercased())
                        .font(.system(size: 34, weight: .bold)).tracking(2)
                }
            }
            Spacer()
            Label(model.online ? "TV ONLINE" : "TV OFFLINE", systemImage: "circle.fill")
                .font(.caption).foregroundStyle(model.online ? .green : .red)
        }
    }
}

struct WebServerSettingsView:View{@EnvironmentObject var model:TVModel;@Environment(\.dismiss) var dismiss;var body:some View{VStack(alignment:.leading,spacing:16){HStack{Text("Web Server").font(.title.bold());Spacer();Button("Done"){model.saveWebServerPreferences();dismiss()}};Text(model.webServerStatus).font(.headline);GroupBox("Host"){VStack(alignment:.leading,spacing:8){Text("Host: \(model.hostNetworkInfo.hostName)");Text("Interfaces: \(model.hostNetworkInfo.interfaces.joined(separator:", "))");Text("IPv4: \(model.hostNetworkInfo.ipv4.joined(separator:", "))");Text("IPv6: \(model.hostNetworkInfo.ipv6.joined(separator:", "))");Text("Wolffe Host ID: \(model.webHostID)");Text("Web address: \(model.preferredWebURL ?? "No LAN IPv4 detected")")}.textSelection(.enabled).padding(8)};GroupBox("Server"){VStack(alignment:.leading,spacing:10){Stepper("Port: \(model.webServerPort)",value:$model.webServerPort,in:1024...65535).disabled(model.webServerRunning);HStack{Text("LAN access code:");Text(model.webAccessCode).font(.title3.monospaced().bold());Button("Regenerate"){model.regenerateAccessCode()}};Divider();Text("Reserved for Alpha 4.0C").font(.caption.bold());Stepper("Maximum authenticated client devices: \(model.webMaxClients)",value:$model.webMaxClients,in:1...20);Text("Default 1. Stored now; enforcement begins when authenticated sessions exist.").font(.caption).foregroundStyle(.secondary)}.padding(8)};HStack{Button("Refresh Network Info"){model.refreshHostNetworkInfo()};Spacer();if model.webServerRunning{Button("Stop Server",role:.destructive){model.stopWebServer()}}else{Button("Start Server"){model.startWebServer()}.buttonStyle(.borderedProminent)}}}.padding(24).frame(minWidth:680,minHeight:560)}}

struct OnboardingView: View {
    @EnvironmentObject var model: TVModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .bottom, endPoint: .top).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: model.onboardingStep == 2 ? "tv.and.hifispeaker.fill" : "network")
                    .font(.system(size: 58)).foregroundStyle(.purple)

                if model.onboardingStep == 0 { welcome }
                else if model.onboardingStep == 1 { checking }
                else { results }
            }
            .padding(42).frame(maxWidth: 760)
        }
        .foregroundStyle(.white)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Text("Welcome to Wolffe TV").font(.largeTitle.bold())
            Text("Wolffe TV controls Roku televisions directly over your local network.")
                .font(.title3).multilineTextAlignment(.center)
            Text("When you continue, macOS may ask whether Wolffe TV can find and communicate with devices on your local network. Choose Allow so Wolffe TV can discover and control your televisions.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Continue") { Task { await model.beginOnboardingNetworkCheck() } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var checking: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Checking your local network…").font(.title2.bold())
            Text("If macOS displays a Local Network permission alert, choose Allow.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var results: some View {
        VStack(spacing: 18) {
            if model.discoveredRokus.isEmpty {
                Text("No Roku TVs Found").font(.largeTitle.bold())
                Text("Wolffe TV could not find a responding Roku TV. This can also happen when a TV is offline or the network blocks discovery.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(model.discoveryDiagnostics).font(.caption.monospaced()).foregroundStyle(.secondary)
                HStack {
                    Button("Open Local Network Settings") { model.openLocalNetworkSettings() }
                    Button("Search Again") { Task { await model.beginOnboardingNetworkCheck() } }.buttonStyle(.borderedProminent)
                }
                Button("Enter IP Manually") { model.completeOnboardingWithManualEntry() }
            } else {
                Text("Roku TVs Found").font(.largeTitle.bold())
                VStack(spacing: 10) {
                    ForEach(model.discoveredRokus) { roku in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(roku.name).font(.headline)
                                Text([roku.host, roku.modelNumber].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.isKnownHost(roku.host) { Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                            else { Button("Add") { Task { await model.addDiscovered(roku) } }.buttonStyle(.borderedProminent) }
                        }.padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text(model.discoveryDiagnostics).font(.caption.monospaced()).foregroundStyle(.secondary)
                HStack {
                    Button("Search Again") { Task { await model.beginOnboardingNetworkCheck() } }
                    Button("Continue") { model.completeOnboarding() }.buttonStyle(.borderedProminent)
                }
                Button("Enter IP Manually") { model.completeOnboardingWithManualEntry() }
            }
        }
    }
}

struct InputButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            HStack {
                Image(systemName: icon).font(.system(size: 32))
                VStack(alignment: .leading) {
                    Text(title).font(.title2.bold()).tracking(2)
                    Text(subtitle).font(.caption).tracking(2).foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(tint.gradient.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

struct DeviceEditorView: View {
    @EnvironmentObject var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let mode: DeviceEditorMode
    @State private var deviceID: UUID?
    @State private var name = ""
    @State private var host = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(mode == .add ? "Add Roku TV" : "Edit Roku TV").font(.title.bold())
                Spacer()
                if model.configured { Button("Cancel") { dismiss() } }
            }
            Text("Enter a friendly name and the local IPv4 address shown under Roku Settings › Network › About.")
                .foregroundStyle(.secondary)
            TextField("TV name", text: $name)
            TextField("TV IP address", text: $host)
            HStack {
                if mode == .editSelected {
                    Button("Delete TV", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Save and Test") {
                    Task { _ = await model.saveDevice(id: deviceID, name: name, host: host) }
                }
                .buttonStyle(.borderedProminent)
            }
            Text(model.message).foregroundStyle(.secondary)
        }
        .padding(28)
        .onAppear {
            if mode == .editSelected, let device = model.selectedDevice {
                deviceID = device.id
                name = device.customName
                host = device.host
            }
        }
        .alert("Delete this TV?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.deleteSelectedDevice() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved device from Wolffe TV. It does not modify or reset the television.")
        }
    }
}

struct RemoteView: View {
    @EnvironmentObject var model: TVModel
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .bottom, endPoint: .top)
                .ignoresSafeArea()
            GeometryReader { proxy in
            let width = proxy.size.width
            let narrow = width < 520
            let columns = narrow ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TV REMOTE").font(.title2.bold()).tracking(2)
                            Text(model.selectedDevice?.customName ?? "No TV selected").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.showingRemote = false } label: { Label("Back to Inputs", systemImage: "chevron.left") }
                    }

                    RemoteTile(title: "HOME", icon: "house.fill", tint: .gray) { await model.send("Home", label: "Home") }

                    VStack(spacing: 10) {
                        RemoteTile(title: nil, icon: "chevron.up", tint: .gray) { await model.send("Up", label: "Up") }.frame(width: 120)
                        HStack(spacing: 10) {
                            RemoteTile(title: nil, icon: "chevron.left", tint: .gray) { await model.send("Left", label: "Left") }
                            RemoteTile(title: "OK", icon: nil, tint: .purple) { await model.send("Select", label: "OK") }
                            RemoteTile(title: nil, icon: "chevron.right", tint: .gray) { await model.send("Right", label: "Right") }
                        }.frame(maxWidth: 440)
                        RemoteTile(title: nil, icon: "chevron.down", tint: .gray) { await model.send("Down", label: "Down") }.frame(width: 120)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        RemoteTile(title: "BACK", icon: "arrow.uturn.backward", tint: .gray) { await model.send("Back", label: "Back") }
                        RemoteTile(title: "PLAY", icon: "playpause.fill", tint: .gray) { await model.send("Play", label: "Play/Pause") }
                        RemoteTile(title: "OPTIONS", icon: "asterisk", tint: .gray) { await model.send("Info", label: "Options") }
                        RemoteTile(title: "VOL −", icon: "speaker.minus.fill", tint: .gray) { await model.send("VolumeDown", label: "Volume down") }
                        RemoteTile(title: "MUTE", icon: "speaker.slash.fill", tint: .gray) { await model.send("VolumeMute", label: "Mute") }
                        RemoteTile(title: "VOL +", icon: "speaker.plus.fill", tint: .gray) { await model.send("VolumeUp", label: "Volume up") }
                        RemoteTile(title: "REPLAY", icon: "gobackward", tint: .gray) { await model.send("InstantReplay", label: "Instant replay") }
                        RemoteTile(title: "POWER ON", icon: "power", tint: .gray) { await model.send("PowerOn", label: "Power on") }
                        RemoteTile(title: "POWER OFF", icon: "power", tint: .red) { await model.send("PowerOff", label: "Power off") }
                    }

                    Text(model.message).foregroundStyle(.secondary).frame(minHeight: 24)
                }
                .padding(26)
                .frame(maxWidth: .infinity)
            }
        }
        }
        .foregroundStyle(.white)
    }
}

struct RemoteTile: View {
    let title: String?
    let icon: String?
    let tint: Color
    let action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            VStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 22, weight: .semibold)) }
                if let title { Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: title == nil ? 48 : 70)
            .contentShape(Rectangle())
            .background(tint.opacity(tint == .red ? 0.72 : 0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct RButton: View {
    let title: String
    let icon: String?
    var emphasized = false
    var destructive = false
    let action: () async -> Void

    init(_ title: String, _ icon: String?, _ emphasized: Bool = false, _ destructive: Bool = false, action: @escaping () async -> Void) {
        self.title = title
        self.icon = icon
        self.emphasized = emphasized
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button { Task { await action() } } label: {
            VStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.title3) }
                if !title.isEmpty { Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.75) }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
        }
        .buttonStyle(.borderedProminent)
        .tint(destructive ? .red : (emphasized ? .purple : .gray.opacity(0.55)))
    }
}
