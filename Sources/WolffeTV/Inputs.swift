import SwiftUI
import Foundation

struct RokuInput: Codable, Identifiable, Hashable {
    var id: String { ecpID }
    var ecpID: String
    var discoveredName: String
    var customName: String?
    var isVisible = true
    var sortOrder: Int
    var displayName: String { let n=(customName ?? "").trimmingCharacters(in:.whitespacesAndNewlines); return n.isEmpty ? discoveredName : n }
    var key: String? { switch ecpID.lowercased() { case "tvinput.hdmi1": return "InputHDMI1"; case "tvinput.hdmi2": return "InputHDMI2"; case "tvinput.hdmi3": return "InputHDMI3"; case "tvinput.hdmi4": return "InputHDMI4"; case "tvinput.cvbs","tvinput.av1": return "InputAV1"; case "tvinput.dtv": return "InputTuner"; default:return nil } }
    var subtitle:String { switch ecpID.lowercased(){case "tvinput.hdmi1":return "HDMI 1";case "tvinput.hdmi2":return "HDMI 2";case "tvinput.hdmi3":return "HDMI 3";case "tvinput.hdmi4":return "HDMI 4";case "tvinput.cvbs","tvinput.av1":return "AV · COMPOSITE";case "tvinput.dtv":return "LIVE TV";default:return ecpID} }
}

final class InputParser:NSObject,XMLParserDelegate {
    var found:[RokuInput]=[]; var appID:String?; var appType:String?; var text=""
    static func parse(_ data:Data)->[RokuInput]{let d=InputParser();let p=XMLParser(data:data);p.delegate=d;return p.parse() ? d.found:[]}
    func parser(_ parser:XMLParser,didStartElement e:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]=[:]){if e=="app"{appID=a["id"];appType=a["type"];text=""}}
    func parser(_ parser:XMLParser,foundCharacters s:String){if appID != nil{text += s}}
    func parser(_ parser:XMLParser,didEndElement e:String,namespaceURI:String?,qualifiedName:String?){if e=="app",let id=appID,appType=="tvin"{let n=text.trimmingCharacters(in:.whitespacesAndNewlines);found.append(RokuInput(ecpID:id,discoveredName:n.isEmpty ? id:n,sortOrder:found.count))};if e=="app"{appID=nil;appType=nil;text=""}}
}

struct InputGrid: View {
 @EnvironmentObject var model: TVModel; let inputs: [RokuInput]
 var body: some View {
  let shown = inputs.filter { $0.isVisible }.sorted { $0.sortOrder < $1.sortOrder }
  return LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 16)], spacing: 16) {
   ForEach(shown) { input in
    Button { Task { await model.activate(input) } } label: {
     VStack(alignment: .leading, spacing: 6) { Text(input.displayName.uppercased()).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.72); Text(input.subtitle).font(.caption).foregroundStyle(.white.opacity(0.7)) }
      .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding().background(.purple.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
    }.buttonStyle(.plain).disabled(input.key == nil)
   }
  }
 }
}
struct InputManagerView:View {
 @EnvironmentObject var model:TVModel; @Environment(\.dismiss) var dismiss; @State var drafts:[RokuInput]=[]
 var body:some View { VStack(spacing:14){HStack{Text("Customize Inputs").font(.title.bold());Spacer();Button("Done"){model.replaceInputs(drafts);dismiss()}}
  if drafts.isEmpty{Text("No inputs detected. Refresh while the TV is reachable.").foregroundStyle(.secondary).frame(maxHeight:.infinity)}else{List{ForEach($drafts){$i in HStack{Toggle("",isOn:$i.isVisible).labelsHidden();TextField(i.discoveredName,text:Binding(get:{i.customName ?? ""},set:{i.customName=$0.isEmpty ? nil:$0}));Button("Restore"){i.customName=nil}}}}}
  HStack{Button("Refresh from TV"){Task{await model.refreshInputs();drafts=model.selectedInputs}}.buttonStyle(.borderedProminent);Spacer();Text(model.message).foregroundStyle(.secondary)}
 }.padding(24).frame(minWidth:620,minHeight:450).onAppear{drafts=model.selectedInputs} }
}
