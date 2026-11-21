import SwiftUI
import Foundation

struct RokuInput: Codable, Identifiable, Hashable {
    var id: String { ecpID }
    var ecpID: String
    var discoveredName: String
    var customName: String?
    var isVisible = true
    var sortOrder: Int
    var iconName: String?
    var accentName: String?

    var displayName: String {
        let name = (customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? discoveredName : name
    }

    var key: String? {
        switch ecpID.lowercased() {
        case "tvinput.hdmi1": return "InputHDMI1"
        case "tvinput.hdmi2": return "InputHDMI2"
        case "tvinput.hdmi3": return "InputHDMI3"
        case "tvinput.hdmi4": return "InputHDMI4"
        case "tvinput.cvbs", "tvinput.av1": return "InputAV1"
        case "tvinput.dtv": return "InputTuner"
        default: return nil
        }
    }

    var subtitle: String {
        switch ecpID.lowercased() {
        case "tvinput.hdmi1": return "HDMI 1"
        case "tvinput.hdmi2": return "HDMI 2"
        case "tvinput.hdmi3": return "HDMI 3"
        case "tvinput.hdmi4": return "HDMI 4"
        case "tvinput.cvbs", "tvinput.av1": return "AV · COMPOSITE"
        case "tvinput.dtv": return "LIVE TV"
        default: return ecpID
        }
    }

    var resolvedIcon: String {
        if let iconName { return iconName }
        if ecpID.lowercased().contains("hdmi") { return "rectangle.on.rectangle" }
        if ecpID.lowercased() == "tvinput.dtv" { return "antenna.radiowaves.left.and.right" }
        return "gamecontroller.fill"
    }
}

enum InputAppearance {
    static let icons = ["rectangle.on.rectangle", "appletv.fill", "desktopcomputer", "gamecontroller.fill", "antenna.radiowaves.left.and.right", "tv.fill"]
    static let colors = ["Purple", "Blue", "Indigo", "Green", "Orange", "Pink", "Gray"]

    static func color(_ name: String?) -> Color {
        switch name {
        case "Blue": return .blue
        case "Indigo": return .indigo
        case "Green": return .green
        case "Orange": return .orange
        case "Pink": return .pink
        case "Gray": return .gray
        default: return .purple
        }
    }
}

final class InputParser: NSObject, XMLParserDelegate {
    var found: [RokuInput] = []
    var appID: String?
    var appType: String?
    var text = ""

    static func parse(_ data: Data) -> [RokuInput] {
        let delegate = InputParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        return parser.parse() ? delegate.found : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String:String] = [:]) {
        if elementName == "app" {
            appID = attributeDict["id"]
            appType = attributeDict["type"]
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if appID != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "app", let id = appID, appType == "tvin" {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            found.append(RokuInput(ecpID: id, discoveredName: name.isEmpty ? id : name, sortOrder: found.count))
        }
        if elementName == "app" { appID = nil; appType = nil; text = "" }
    }
}

struct InputGrid: View {
    @EnvironmentObject var model: TVModel
    let inputs: [RokuInput]

    var body: some View {
        let shown = inputs.filter { $0.isVisible }.sorted { $0.sortOrder < $1.sortOrder }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 16)], spacing: 16) {
            ForEach(shown) { input in
                Button { Task { await model.activate(input) } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: input.resolvedIcon).font(.system(size: 28, weight: .semibold))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(input.displayName.uppercased()).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.72)
                            Text(input.subtitle).font(.caption).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                    .padding()
                    .foregroundStyle(.white)
                    .background(InputAppearance.color(input.accentName).opacity(0.66), in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .disabled(input.key == nil)
            }
        }
    }
}

struct InputManagerView: View {
    @EnvironmentObject var model: TVModel
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [RokuInput] = []

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Customize Inputs").font(.title.bold())
                    Text(model.selectedDevice?.customName ?? "No TV selected").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { normalizeOrder(); model.replaceInputs(drafts); dismiss() }
            }

            if drafts.isEmpty {
                Text("No inputs detected. Refresh while the TV is reachable.")
                    .foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(drafts.indices), id: \.self) { index in
                        inputEditor(index)
                    }
                }
            }

            HStack {
                Button("Refresh from TV") { Task { await model.refreshInputs(); drafts = model.selectedInputs.sorted { $0.sortOrder < $1.sortOrder } } }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text(model.message).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { drafts = model.selectedInputs.sorted { $0.sortOrder < $1.sortOrder } }
    }

    private func inputEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Visible", isOn: $drafts[index].isVisible).toggleStyle(.checkbox)
                TextField(drafts[index].discoveredName, text: Binding(
                    get: { drafts[index].customName ?? "" },
                    set: { drafts[index].customName = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Button("Restore Name") { drafts[index].customName = nil }
            }

            HStack {
                Text("Detected: \(drafts[index].discoveredName)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index == drafts.count - 1)
            }

            HStack {
                Picker("Icon", selection: Binding(
                    get: { drafts[index].iconName ?? drafts[index].resolvedIcon },
                    set: { drafts[index].iconName = $0 }
                )) {
                    ForEach(InputAppearance.icons, id: \.self) { icon in Label(icon, systemImage: icon).tag(icon) }
                }
                .pickerStyle(.menu)

                Picker("Color", selection: Binding(
                    get: { drafts[index].accentName ?? "Purple" },
                    set: { drafts[index].accentName = $0 }
                )) {
                    ForEach(InputAppearance.colors, id: \.self) { name in Text(name).tag(name) }
                }
                .pickerStyle(.menu)

                Spacer()
                Label(drafts[index].displayName, systemImage: drafts[index].resolvedIcon)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(InputAppearance.color(drafts[index].accentName).opacity(0.55), in: Capsule())
            }
        }
        .padding(.vertical, 7)
    }

    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard drafts.indices.contains(destination) else { return }
        drafts.swapAt(index, destination)
        normalizeOrder()
    }

    private func normalizeOrder() {
        for index in drafts.indices { drafts[index].sortOrder = index }
    }
}
