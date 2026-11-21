import SwiftUI
import Foundation

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
    @Published var isDiscovering = false
    @Published var discoveredRokus: [DiscoveredRoku] = []

    private let stateKey = "wolffeTVState.v1"
    private let defaults = UserDefaults.standard

    var devices: [RokuDevice] { state.devices }
    var selectedDevice: RokuDevice? {
        guard let id = state.selectedDeviceID else { return state.devices.first }
        return state.devices.first(where: { $0.id == id }) ?? state.devices.first
    }
    var configured: Bool { selectedDevice != nil }
    var selectedInputs:[RokuInput] { selectedDevice?.inputs ?? [] }

    init() {
        state = WolffeTVState()
        loadOrMigrateState()
        if configured {
            Task { await checkStatus() }
        } else {
            editorMode = .add
            showingDeviceEditor = true
        }
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
    func discoverRokus() async { isDiscovering=true;message="";discoveredRokus=await RokuDiscovery.discover();isDiscovering=false;message=discoveredRokus.isEmpty ? "No Roku TVs discovered." : "✓ Found \(discoveredRokus.count) Roku TV(s)" }
    func addDiscovered(_ r:DiscoveredRoku) async { guard !isKnownHost(r.host) else{message="That TV is already added.";return};let d=RokuDevice(customName:r.name,host:r.host,discoveredName:r.name,modelNumber:r.modelNumber,softwareVersion:r.softwareVersion);state.devices.append(d);state.selectedDeviceID=d.id;persist();await checkStatus();await refreshInputs();message="✓ Added \(r.name)" }
    func replaceInputs(_ v:[RokuInput]) { guard let id=selectedDevice?.id,let i=state.devices.firstIndex(where:{$0.id==id}) else{return};state.devices[i].inputs=v;persist() }
    func refreshInputs() async { guard let d=selectedDevice,let u=URL(string:"http://\(d.host):8060/query/apps") else{return};do{var r=URLRequest(url:u);r.timeoutInterval=5;let(data,res)=try await URLSession.shared.data(for:r);guard(res as? HTTPURLResponse)?.statusCode==200 else{throw URLError(.badServerResponse)};let fresh=InputParser.parse(data);guard !fresh.isEmpty else{message="No physical inputs detected.";return};let old=Dictionary(uniqueKeysWithValues:selectedInputs.map{($0.ecpID,$0)});let merged=fresh.map{f->RokuInput in var x=f;if let o=old[f.ecpID]{x.customName=o.customName;x.isVisible=o.isVisible;x.sortOrder=o.sortOrder};return x};replaceInputs(merged);message="✓ Detected \(merged.count) inputs for \(d.customName)"}catch{message="Could not refresh inputs from \(d.customName)."} }
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
            if model.showingRemote {
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
                Text("LOCAL CONTROL · v4 ALPHA 3.4.2").font(.caption).tracking(3).foregroundStyle(.purple)
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
