// CLT-only packaging: emit the fixed widget configuration schema from actual Swift types.
// Full Xcode builds use ExtractAppIntentsMetadata automatically.
import Foundation
import AppIntents
import ProxPulseWidgetUI

let availability: [String: Any] = ["LNPlatformNameWildcard": ["introducedVersion": "*"]]
let intentName = String(describing: SelectMachineIntent.self)
let entityName = String(describing: MachineEntity.self)
let queryName = String(describing: MachineEntityQuery.self)
func mangled(_ type: Any.Type) -> String {
    guard let value = _mangledTypeName(type), _typeByName(value) != nil else { fatalError("Missing runtime type metadata") }
    return value
}
let common: [String: Any] = ["availabilityAnnotations": availability, "mangledTypeNameByBundleIdentifier": [:], "effectiveBundleIdentifiers": []]
let query = common.merging(["mangledTypeName": mangled(MachineEntityQuery.self), "identifier": queryName, "queryType": queryName, "entityType": entityName, "capabilities": 0, "sortingOptions": [], "parameters": []]) { _, new in new }
let entity = common.merging(["mangledTypeName": mangled(MachineEntity.self), "displayTypeName": ["key": "Машина / Machine"], "typeName": entityName, "transient": false, "properties": [], "systemProtocolMetadata": []]) { _, new in new }
let action = common.merging([
    "mangledTypeName": mangled(SelectMachineIntent.self), "identifier": intentName,
    "title": ["key": "Машина / Machine"], "outputFlags": 8, "isDiscoverable": true,
    "typeSpecificMetadata": [], "requiredCapabilities": [], "authenticationPolicy": 0,
    "presentationStyle": 0, "openAppWhenRun": false,
    "systemProtocols": ["com.apple.link.systemProtocol.WidgetConfiguration"],
    "systemProtocolMetadata": ["com.apple.link.systemProtocol.WidgetConfiguration", ["empty": [:]]] as [Any],
    "parameters": [["name": "machine", "title": ["key": "Машина / Machine"], "isOptional": true,
                    "valueType": ["entity": ["wrapper": ["typeName": entityName]]], "dynamicOptionsSupport": 2,
                    "isInput": false, "inputConnectionBehavior": 0, "typeSpecificMetadata": [], "resolvableInputTypes": []]]
]) { _, new in new }
let payload: [String: Any] = ["generator": ["name": "ProxPulse CLT metadata packager", "version": "1.0"], "version": 1, "actions": [intentName: action], "entities": [entityName: entity], "queries": [queryName: query], "enums": [], "autoShortcuts": [], "negativePhrases": [], "shortcutTileColor": 14]
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: directory.appendingPathComponent("extract.actionsdata"))
try JSONSerialization.data(withJSONObject: ["version": "3.0", "toolsVersion": "15.0"]).write(to: directory.appendingPathComponent("version.json"))
print("PASS: packaged SelectMachineIntent, MachineEntity and query metadata with resolvable Swift types")
