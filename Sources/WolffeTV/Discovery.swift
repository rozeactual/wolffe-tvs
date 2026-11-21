import SwiftUI
import Foundation
import Network

struct DiscoveredRoku: Identifiable, Hashable {
    let id: String
    let host: String
    let name: String
    let modelNumber: String?
    let softwareVersion: String?
}

final class DeviceInfoParser: NSObject, XMLParserDelegate {
    var values: [String:String] = [:]
    private var text = ""
    static func parse(_ data:Data)->[String:String]{let d=DeviceInfoParser();let p=XMLParser(data:data);p.delegate=d;_ = p.parse();return d.values}
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes attributeDict:[String:String]=[:]){text=""}
    func parser(_ parser:XMLParser,foundCharacters string:String){text += string}
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName qName:String?){let v=text.trimmingCharacters(in:.whitespacesAndNewlines);if !v.isEmpty{values[elementName]=v};text=""}
}

enum RokuDiscovery {
    static func discover(timeout:TimeInterval=3.0) async->[DiscoveredRoku]{
        let urls=await locations(timeout:timeout);var out:[DiscoveredRoku]=[]
        for base in urls { guard let host=base.host else{continue};do{var r=URLRequest(url:base.appendingPathComponent("query/device-info"));r.timeoutInterval=4;let(data,res)=try await URLSession.shared.data(for:r);guard(res as? HTTPURLResponse)?.statusCode==200 else{continue};let i=DeviceInfoParser.parse(data);out.append(DiscoveredRoku(id:base.absoluteString,host:host,name:i["user-device-name"] ?? i["friendly-device-name"] ?? i["model-name"] ?? "Roku TV",modelNumber:i["model-number"],softwareVersion:i["software-version"]))}catch{continue}}
        return out.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
    }
    private static func locations(timeout:TimeInterval) async->[URL]{await withCheckedContinuation{c in
        let q=DispatchQueue(label:"com.wolffetv.ssdp");let x=NWConnection(host:"239.255.255.250",port:1900,using:.udp);var found=Set<URL>();var done=false
        func finish(){guard !done else{return};done=true;x.cancel();c.resume(returning:Array(found))}
        func receive(){guard !done else{return};x.receiveMessage{data,_,_,error in if let data,let response=String(data:data,encoding:.utf8){for line in response.components(separatedBy:.newlines){let p=line.split(separator:":",maxSplits:1,omittingEmptySubsequences:false);if p.count==2,p[0].trimmingCharacters(in:.whitespacesAndNewlines).lowercased()=="location",let u=URL(string:p[1].trimmingCharacters(in:.whitespacesAndNewlines)){found.insert(u)}}};if error==nil{receive()}}}
        x.stateUpdateHandler={state in if case .ready=state{let probe="M-SEARCH * HTTP/1.1\r\nHost: 239.255.255.250:1900\r\nMan: \"ssdp:discover\"\r\nST: roku:ecp\r\nMX: 2\r\n\r\n";x.send(content:probe.data(using:.utf8),completion:.contentProcessed{_ in});receive();q.asyncAfter(deadline:.now()+timeout){finish()}};if case .failed=state{finish()}}
        x.start(queue:q);q.asyncAfter(deadline:.now()+timeout+1){finish()}
    }}
}

struct DiscoveryView:View {
 @EnvironmentObject var model:TVModel;@Environment(\.dismiss)var dismiss
 var body:some View{VStack(spacing:16){HStack{VStack(alignment:.leading){Text("Discover Roku TVs").font(.title.bold());Text("Search the local network for Roku ECP devices.").foregroundStyle(.secondary)};Spacer();Button("Done"){dismiss()}}
  if model.isDiscovering{ProgressView("Looking for Roku TVs…").frame(maxWidth:.infinity,maxHeight:.infinity)}else if model.discoveredRokus.isEmpty{VStack{Image(systemName:"wifi.exclamationmark").font(.largeTitle);Text("No Roku TVs found").font(.headline);Text("Try again or enter the IP address manually.").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity)}else{List(model.discoveredRokus){r in HStack{VStack(alignment:.leading){Text(r.name).font(.headline);Text([r.host,r.modelNumber].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)};Spacer();if model.isKnownHost(r.host){Label("Added",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}else{Button("Add"){Task{await model.addDiscovered(r)}}.buttonStyle(.borderedProminent)}}}}
  HStack{Button("Search Again"){Task{await model.discoverRokus()}}.buttonStyle(.borderedProminent).disabled(model.isDiscovering);Button("Enter IP Manually"){dismiss();model.openAddDevice()};Spacer();Text(model.message).foregroundStyle(.secondary)}
 }.padding(24).frame(minWidth:650,minHeight:470).task{if model.discoveredRokus.isEmpty{await model.discoverRokus()}}}
}
