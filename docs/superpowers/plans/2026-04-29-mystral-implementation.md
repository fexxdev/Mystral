# Mystral Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that reads temperature sensors and controls fan speeds on Apple Silicon Macs via SMC.

**Architecture:** SwiftUI app with AppKit integration for NSStatusItem. IOKit bridge for SMC read/write. Protocol-based service layer for testability. XPC privileged helper for fan write operations. JSON file storage for profiles.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSStatusItem), IOKit (SMC), XPC Services, Swift Charts, XcodeGen

**Spec:** `docs/superpowers/specs/2026-04-29-mystral-design.md`

---

## File Map

```
Mystral/
├── project.yml                    — XcodeGen project definition
├── .gitignore
├── Mystral/
│   ├── Info.plist
│   ├── Mystral.entitlements
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/Contents.json
│   ├── Localizable.xcstrings
│   ├── App/
│   │   ├── MystralApp.swift       — @main entry, app lifecycle
│   │   └── AppDelegate.swift      — NSApplicationDelegate, window mgmt
│   ├── MenuBar/
│   │   └── MenuBarManager.swift   — NSStatusItem, configurable display
│   ├── Models/
│   │   ├── Profile.swift          — Profile, CurvePoint
│   │   ├── Sensor.swift           — Sensor model
│   │   └── Fan.swift              — Fan, FanMode models
│   ├── Services/
│   │   ├── SMCKit.swift           — Low-level IOKit SMC bridge
│   │   ├── SMCService.swift       — High-level SMC read/write (protocol-based)
│   │   ├── FanController.swift    — Polling loop, curve interpolation
│   │   └── ProfileManager.swift   — Profile CRUD, JSON storage
│   ├── Views/
│   │   ├── MainView.swift         — NavigationSplitView with sidebar
│   │   ├── DashboardView.swift    — Overview: temps, fans, active profile
│   │   ├── SensorsView.swift      — Sensor table with sparklines
│   │   ├── FansView.swift         — Fan list with manual override
│   │   ├── ProfilesView.swift     — Profile list, add/duplicate/delete
│   │   ├── CurveEditorView.swift  — Draggable chart + editable table
│   │   └── SettingsView.swift     — App settings
│   └── Presets/
│       ├── silent.json
│       ├── balanced.json
│       ├── performance.json
│       └── fullblast.json
├── MystralHelper/
│   ├── Info.plist
│   ├── MystralHelper.entitlements
│   ├── main.swift                 — XPC listener entry
│   └── HelperProtocol.swift       — XPC protocol definition
├── MystralTests/
│   ├── CurveInterpolationTests.swift
│   ├── ProfileManagerTests.swift
│   └── SMCServiceTests.swift
├── README.md
└── LICENSE
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `Mystral/Info.plist`
- Create: `Mystral/Mystral.entitlements`
- Create: `Mystral/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Mystral/App/MystralApp.swift` (minimal placeholder)

- [ ] **Step 1: Install XcodeGen**

```bash
brew install xcodegen
```

- [ ] **Step 2: Create .gitignore**

Create `.gitignore`:

```gitignore
# Xcode
*.xcodeproj/
*.xcworkspace/
xcuserdata/
DerivedData/
build/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.xccheckout
*.moved-aside

# Swift Package Manager
.build/
.swiftpm/
Packages/

# macOS
.DS_Store
*.dSYM.zip
*.dSYM

# App
*.app
*.ipa
```

- [ ] **Step 3: Create project.yml**

Create `project.yml`:

```yaml
name: Mystral
options:
  bundleIdPrefix: com.fexxdev
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"

targets:
  Mystral:
    type: application
    platform: macOS
    sources:
      - Mystral
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fexxdev.Mystral
        INFOPLIST_FILE: Mystral/Info.plist
        CODE_SIGN_ENTITLEMENTS: Mystral/Mystral.entitlements
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks"
        GENERATE_INFOPLIST_FILE: false
    entitlements:
      path: Mystral/Mystral.entitlements

  MystralTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - MystralTests
    dependencies:
      - target: Mystral
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fexxdev.MystralTests
```

- [ ] **Step 4: Create Info.plist**

Create `Mystral/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Mystral</string>
    <key>CFBundleDisplayName</key>
    <string>Mystral</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMainStoryboardFile</key>
    <string></string>
</dict>
</plist>
```

- [ ] **Step 5: Create entitlements**

Create `Mystral/Mystral.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 6: Create empty Assets.xcassets**

Create `Mystral/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    { "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

Create `Mystral/Assets.xcassets/Contents.json`:

```json
{
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 7: Create minimal MystralApp.swift**

Create `Mystral/App/MystralApp.swift`:

```swift
import SwiftUI

@main
struct MystralApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Mystral")
        }
    }
}
```

- [ ] **Step 8: Create MystralTests directory with placeholder**

Create `MystralTests/MystralTests.swift`:

```swift
import XCTest

final class MystralTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 9: Generate Xcode project and verify build**

```bash
cd Mystral && xcodegen generate
xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add .gitignore project.yml Mystral/ MystralTests/
git commit -m "feat: project scaffolding with XcodeGen, Info.plist, entitlements"
```

---

### Task 2: Data Models

**Files:**
- Create: `Mystral/Models/Profile.swift`
- Create: `Mystral/Models/Sensor.swift`
- Create: `Mystral/Models/Fan.swift`

- [ ] **Step 1: Write tests for CurvePoint and Profile**

Create `MystralTests/ProfileModelTests.swift`:

```swift
import XCTest
@testable import Mystral

final class ProfileModelTests: XCTestCase {
    func testCurvePointCodable() throws {
        let point = CurvePoint(temperature: 65.0, fanPercentage: 50.0)
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(CurvePoint.self, from: data)
        XCTAssertEqual(decoded.temperature, 65.0)
        XCTAssertEqual(decoded.fanPercentage, 50.0)
    }

    func testProfileCodable() throws {
        let profile = Profile(
            name: "Test",
            icon: "fan",
            isPreset: false,
            curvePoints: [
                CurvePoint(temperature: 30, fanPercentage: 10),
                CurvePoint(temperature: 90, fanPercentage: 100)
            ],
            sensorKey: "Tp09"
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.curvePoints.count, 2)
        XCTAssertEqual(decoded.sensorKey, "Tp09")
        XCTAssertFalse(decoded.isPreset)
    }

    func testCurvePointsSortedByTemperature() {
        let points = [
            CurvePoint(temperature: 90, fanPercentage: 100),
            CurvePoint(temperature: 30, fanPercentage: 10),
            CurvePoint(temperature: 60, fanPercentage: 50)
        ]
        let sorted = points.sortedByTemperature()
        XCTAssertEqual(sorted[0].temperature, 30)
        XCTAssertEqual(sorted[1].temperature, 60)
        XCTAssertEqual(sorted[2].temperature, 90)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild test -project Mystral.xcodeproj -scheme MystralTests -configuration Debug
```

Expected: FAIL — models not defined yet.

- [ ] **Step 3: Implement Profile.swift**

Create `Mystral/Models/Profile.swift`:

```swift
import Foundation

struct CurvePoint: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var temperature: Double
    var fanPercentage: Double

    enum CodingKeys: String, CodingKey {
        case temperature, fanPercentage
    }
}

extension Array where Element == CurvePoint {
    func sortedByTemperature() -> [CurvePoint] {
        sorted { $0.temperature < $1.temperature }
    }
}

struct Profile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var isPreset: Bool
    var curvePoints: [CurvePoint]
    var sensorKey: String

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "fan",
        isPreset: Bool = false,
        curvePoints: [CurvePoint],
        sensorKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isPreset = isPreset
        self.curvePoints = curvePoints
        self.sensorKey = sensorKey
    }
}
```

- [ ] **Step 4: Implement Sensor.swift**

Create `Mystral/Models/Sensor.swift`:

```swift
import Foundation

struct Sensor: Identifiable, Sendable {
    let id: String
    let name: String
    var temperature: Double
    var history: [Double]

    init(id: String, name: String, temperature: Double = 0, history: [Double] = []) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.history = history
    }

    mutating func recordTemperature(_ temp: Double, maxHistory: Int = 30) {
        temperature = temp
        history.append(temp)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }
}
```

- [ ] **Step 5: Implement Fan.swift**

Create `Mystral/Models/Fan.swift`:

```swift
import Foundation

enum FanMode: Int, Sendable {
    case auto = 0
    case forced = 1
}

struct Fan: Identifiable, Sendable {
    let id: Int
    let name: String
    var currentRPM: Int
    var targetRPM: Int
    var minRPM: Int
    var maxRPM: Int
    var mode: FanMode

    var percentage: Double {
        guard maxRPM > minRPM else { return 0 }
        return Double(currentRPM - minRPM) / Double(maxRPM - minRPM) * 100.0
    }
}
```

- [ ] **Step 6: Regenerate Xcode project and run tests**

```bash
cd Mystral && xcodegen generate
xcodebuild test -project Mystral.xcodeproj -scheme MystralTests -configuration Debug
```

Expected: ALL TESTS PASSED

- [ ] **Step 7: Commit**

```bash
git add Mystral/Models/ MystralTests/ProfileModelTests.swift
git commit -m "feat: add data models — Profile, CurvePoint, Sensor, Fan"
```

---

### Task 3: SMC Bridge (IOKit)

**Files:**
- Create: `Mystral/Services/SMCKit.swift`

This is the low-level IOKit bridge that communicates with the AppleSMC kernel driver. It handles opening/closing the SMC connection, reading sensor values, reading fan info, and writing fan targets.

- [ ] **Step 1: Create SMCKit.swift with types and connection management**

Create `Mystral/Services/SMCKit.swift`:

```swift
import Foundation
import IOKit

enum SMCError: Error, LocalizedError {
    case driverNotFound
    case failedToOpen
    case keyNotFound(String)
    case readError(kern_return_t)
    case writeError(kern_return_t)
    case unsupportedDataType(String)

    var errorDescription: String? {
        switch self {
        case .driverNotFound: "AppleSMC driver not found"
        case .failedToOpen: "Failed to open SMC connection"
        case .keyNotFound(let key): "SMC key not found: \(key)"
        case .readError(let code): "SMC read error: \(code)"
        case .writeError(let code): "SMC write error: \(code)"
        case .unsupportedDataType(let type): "Unsupported SMC data type: \(type)"
        }
    }
}

final class SMCKit: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private static let smcHandlerSelector: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdWriteBytes: UInt8 = 6
    private static let cmdReadIndex: UInt8 = 8
    private static let cmdReadKeyInfo: UInt8 = 9

    struct DataType {
        static let flt = dataTypeToUInt32("flt ")
        static let sp78 = dataTypeToUInt32("sp78")
        static let fpe2 = dataTypeToUInt32("fpe2")
        static let ui8 = dataTypeToUInt32("ui8 ")
        static let ui16 = dataTypeToUInt32("ui16")
        static let ui32 = dataTypeToUInt32("ui32")
        static let flag = dataTypeToUInt32("flag")
    }

    // MARK: - SMC kernel structures

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    // MARK: - Connection

    func open() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else {
            throw SMCError.driverNotFound
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else {
            throw SMCError.failedToOpen
        }
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    deinit {
        close()
    }

    // MARK: - Key Utilities

    static func fourCharCode(_ key: String) -> UInt32 {
        var result: UInt32 = 0
        for char in key.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    static func fourCharString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private static func dataTypeToUInt32(_ type: String) -> UInt32 {
        fourCharCode(type)
    }

    // MARK: - Low-level SMC calls

    private func callSMC(_ input: inout SMCKeyData) throws -> SMCKeyData {
        lock.lock()
        defer { lock.unlock() }

        var output = SMCKeyData()
        var inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = IOConnectCallStructMethod(
            connection,
            Self.smcHandlerSelector,
            &input,
            inputSize,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            throw SMCError.readError(result)
        }
        return output
    }

    private func readKeyInfo(key: UInt32) throws -> SMCKeyInfoData {
        var input = SMCKeyData()
        input.key = key
        input.data8 = Self.cmdReadKeyInfo
        let output = try callSMC(&input)
        return output.keyInfo
    }

    // MARK: - Public Read API

    func readRawBytes(key: String) throws -> (bytes: [UInt8], dataType: UInt32, dataSize: UInt32) {
        let keyCode = Self.fourCharCode(key)
        let info = try readKeyInfo(key: keyCode)

        var input = SMCKeyData()
        input.key = keyCode
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Self.cmdReadBytes
        let output = try callSMC(&input)

        let mirror = Mirror(reflecting: output.bytes)
        let bytes = mirror.children.prefix(Int(info.dataSize)).map { $0.value as! UInt8 }
        return (bytes, info.dataType, info.dataSize)
    }

    func readFloat(key: String) throws -> Double {
        let (bytes, dataType, _) = try readRawBytes(key: key)

        switch dataType {
        case DataType.flt:
            guard bytes.count >= 4 else { return 0 }
            let bits = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 |
                       UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(Float(bitPattern: bits))

        case DataType.sp78:
            guard bytes.count >= 2 else { return 0 }
            let raw = Int16(Int16(bytes[0]) << 8 | Int16(bytes[1]))
            return Double(raw) / 256.0

        case DataType.fpe2:
            guard bytes.count >= 2 else { return 0 }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0

        case DataType.ui8:
            return Double(bytes[0])

        case DataType.ui16:
            guard bytes.count >= 2 else { return 0 }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))

        default:
            throw SMCError.unsupportedDataType(Self.fourCharString(dataType))
        }
    }

    func readInteger(key: String) throws -> Int {
        Int(try readFloat(key: key))
    }

    // MARK: - Public Write API

    func writeBytes(key: String, dataType: UInt32, bytes: [UInt8]) throws {
        let keyCode = Self.fourCharCode(key)
        let info = try readKeyInfo(key: keyCode)

        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = Self.cmdWriteBytes
        input.keyInfo.dataSize = info.dataSize

        var tupleBytes = input.bytes
        withUnsafeMutableBytes(of: &tupleBytes) { ptr in
            for (i, byte) in bytes.prefix(Int(info.dataSize)).enumerated() {
                ptr[i] = byte
            }
        }
        input.bytes = tupleBytes

        let result = try callSMC(&input)
        if result.result != 0 {
            throw SMCError.writeError(kern_return_t(result.result))
        }
    }

    func writeFpe2(key: String, value: Double) throws {
        let raw = UInt16(max(0, min(value * 4.0, Double(UInt16.max))))
        try writeBytes(key: key, dataType: DataType.fpe2, bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
    }

    func writeUInt8(key: String, value: UInt8) throws {
        try writeBytes(key: key, dataType: DataType.ui8, bytes: [value])
    }

    // MARK: - Key Enumeration

    func keyCount() throws -> Int {
        try readInteger(key: "#KEY")
    }

    func keyAtIndex(_ index: Int) throws -> String {
        var input = SMCKeyData()
        input.data8 = Self.cmdReadIndex
        input.data32 = UInt32(index)
        let output = try callSMC(&input)
        return Self.fourCharString(output.key)
    }

    func allKeys() throws -> [String] {
        let count = try keyCount()
        return try (0..<count).map { try keyAtIndex($0) }
    }

    func temperatureKeys() throws -> [String] {
        try allKeys().filter { $0.hasPrefix("T") }
    }
}
```

- [ ] **Step 2: Regenerate project and build**

```bash
cd Mystral && xcodegen generate
xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Mystral/Services/SMCKit.swift
git commit -m "feat: add SMCKit — low-level IOKit bridge for AppleSMC"
```

---

### Task 4: SMC Service Layer

**Files:**
- Create: `Mystral/Services/SMCService.swift`
- Create: `MystralTests/SMCServiceTests.swift`

Protocol-based service wrapping SMCKit. Defines `SMCServiceProtocol` so the rest of the app can be tested with a mock.

- [ ] **Step 1: Write tests for SMCService using mock**

Create `MystralTests/SMCServiceTests.swift`:

```swift
import XCTest
@testable import Mystral

final class MockSMCService: SMCServiceProtocol {
    var sensors: [Sensor] = [
        Sensor(id: "Tp09", name: "CPU Efficiency Core 1", temperature: 45.0),
        Sensor(id: "Tp01", name: "CPU Performance Core 1", temperature: 62.0)
    ]

    var fans: [Fan] = [
        Fan(id: 0, name: "Left Fan", currentRPM: 1200, targetRPM: 1200,
            minRPM: 1000, maxRPM: 5500, mode: .auto),
        Fan(id: 1, name: "Right Fan", currentRPM: 1200, targetRPM: 1200,
            minRPM: 1000, maxRPM: 5500, mode: .auto)
    ]

    var lastSetFanIndex: Int?
    var lastSetPercentage: Double?
    var lastSetMode: FanMode?

    func getAllSensors() throws -> [Sensor] { sensors }
    func readTemperature(key: String) throws -> Double {
        sensors.first { $0.id == key }?.temperature ?? 0
    }
    func getAllFans() throws -> [Fan] { fans }
    func readFanSpeed(index: Int) throws -> Int { fans[index].currentRPM }
    func setFanSpeed(index: Int, percentage: Double) throws {
        lastSetFanIndex = index
        lastSetPercentage = percentage
    }
    func setFanMode(index: Int, mode: FanMode) throws {
        lastSetMode = mode
    }
}

final class SMCServiceTests: XCTestCase {
    func testMockRetursSensors() throws {
        let svc = MockSMCService()
        let sensors = try svc.getAllSensors()
        XCTAssertEqual(sensors.count, 2)
        XCTAssertEqual(sensors[0].id, "Tp09")
    }

    func testMockReturnsFans() throws {
        let svc = MockSMCService()
        let fans = try svc.getAllFans()
        XCTAssertEqual(fans.count, 2)
        XCTAssertEqual(fans[0].maxRPM, 5500)
    }

    func testMockSetFanSpeed() throws {
        let svc = MockSMCService()
        try svc.setFanSpeed(index: 0, percentage: 75.0)
        XCTAssertEqual(svc.lastSetFanIndex, 0)
        XCTAssertEqual(svc.lastSetPercentage, 75.0)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodegen generate && xcodebuild test -project Mystral.xcodeproj -scheme MystralTests
```

Expected: FAIL — `SMCServiceProtocol` not defined yet.

- [ ] **Step 3: Implement SMCService.swift**

Create `Mystral/Services/SMCService.swift`:

```swift
import Foundation

protocol SMCServiceProtocol: Sendable {
    func getAllSensors() throws -> [Sensor]
    func readTemperature(key: String) throws -> Double
    func getAllFans() throws -> [Fan]
    func readFanSpeed(index: Int) throws -> Int
    func setFanSpeed(index: Int, percentage: Double) throws
    func setFanMode(index: Int, mode: FanMode) throws
}

final class SMCService: SMCServiceProtocol {
    private let smc = SMCKit()

    private static let knownSensorNames: [String: String] = [
        "Tp01": "CPU Performance Core 1",
        "Tp02": "CPU Performance Core 2",
        "Tp03": "CPU Performance Core 3",
        "Tp04": "CPU Performance Core 4",
        "Tp05": "CPU Performance Core 5",
        "Tp06": "CPU Performance Core 6",
        "Tp09": "CPU Efficiency Core 1",
        "Tp0A": "CPU Efficiency Core 2",
        "Tp0B": "CPU Efficiency Core 3",
        "Tp0C": "CPU Efficiency Core 4",
        "Tg0a": "GPU Core 1",
        "Tg0b": "GPU Core 2",
        "Tg0c": "GPU Core 3",
        "Tg0d": "GPU Core 4",
        "TaLP": "Airflow Left",
        "TaRP": "Airflow Right",
        "Tm01": "Memory 1",
        "Tm02": "Memory 2",
        "Ts0S": "SSD",
    ]

    init() throws {
        try smc.open()
    }

    deinit {
        smc.close()
    }

    func getAllSensors() throws -> [Sensor] {
        let keys = try smc.temperatureKeys()
        return keys.compactMap { key in
            guard let temp = try? smc.readFloat(key: key), temp > 0, temp < 150 else {
                return nil
            }
            let name = Self.knownSensorNames[key] ?? key
            return Sensor(id: key, name: name, temperature: temp)
        }
    }

    func readTemperature(key: String) throws -> Double {
        try smc.readFloat(key: key)
    }

    func getAllFans() throws -> [Fan] {
        let fanCountKey = "FNum"
        let count = try smc.readInteger(key: fanCountKey)
        return (0..<count).compactMap { i in
            let prefix = "F\(i)"
            guard let actual = try? smc.readFloat(key: "\(prefix)Ac"),
                  let min = try? smc.readFloat(key: "\(prefix)Mn"),
                  let max = try? smc.readFloat(key: "\(prefix)Mx") else {
                return nil
            }
            let target = (try? smc.readFloat(key: "\(prefix)Tg")) ?? actual
            let modeRaw = (try? smc.readInteger(key: "\(prefix)Md")) ?? 0
            let name = i == 0 ? "Left Fan" : "Right Fan"
            return Fan(
                id: i,
                name: name,
                currentRPM: Int(actual),
                targetRPM: Int(target),
                minRPM: Int(min),
                maxRPM: Int(max),
                mode: FanMode(rawValue: modeRaw) ?? .auto
            )
        }
    }

    func readFanSpeed(index: Int) throws -> Int {
        try smc.readInteger(key: "F\(index)Ac")
    }

    func setFanSpeed(index: Int, percentage: Double) throws {
        let fans = try getAllFans()
        guard index < fans.count else { return }
        let fan = fans[index]
        let targetRPM = Double(fan.minRPM) + (Double(fan.maxRPM - fan.minRPM) * percentage / 100.0)
        try smc.writeFpe2(key: "F\(index)Tg", value: targetRPM)
    }

    func setFanMode(index: Int, mode: FanMode) throws {
        try smc.writeUInt8(key: "F\(index)Md", value: UInt8(mode.rawValue))
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodegen generate && xcodebuild test -project Mystral.xcodeproj -scheme MystralTests
```

Expected: ALL TESTS PASSED (tests use mock, not real SMC)

- [ ] **Step 5: Commit**

```bash
git add Mystral/Services/SMCService.swift MystralTests/SMCServiceTests.swift
git commit -m "feat: add SMCService protocol and implementation with mock for testing"
```

---

### Task 5: Profile Manager

**Files:**
- Create: `Mystral/Services/ProfileManager.swift`
- Create: `Mystral/Presets/silent.json`
- Create: `Mystral/Presets/balanced.json`
- Create: `Mystral/Presets/performance.json`
- Create: `Mystral/Presets/fullblast.json`
- Create: `MystralTests/ProfileManagerTests.swift`

- [ ] **Step 1: Write ProfileManager tests**

Create `MystralTests/ProfileManagerTests.swift`:

```swift
import XCTest
@testable import Mystral

final class ProfileManagerTests: XCTestCase {
    var tempDir: URL!
    var manager: ProfileManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = ProfileManager(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPresetsAreLoaded() {
        XCTAssertEqual(manager.presets.count, 4)
        XCTAssertTrue(manager.presets.allSatisfy(\.isPreset))
    }

    func testPresetNames() {
        let names = Set(manager.presets.map(\.name))
        XCTAssertTrue(names.contains("Silent"))
        XCTAssertTrue(names.contains("Balanced"))
        XCTAssertTrue(names.contains("Performance"))
        XCTAssertTrue(names.contains("Full Blast"))
    }

    func testAddCustomProfile() throws {
        let profile = Profile(
            name: "My Profile",
            curvePoints: [
                CurvePoint(temperature: 30, fanPercentage: 20),
                CurvePoint(temperature: 80, fanPercentage: 90)
            ]
        )
        try manager.saveCustomProfile(profile)
        XCTAssertEqual(manager.customProfiles.count, 1)
        XCTAssertEqual(manager.customProfiles[0].name, "My Profile")
    }

    func testCustomProfilePersistence() throws {
        let profile = Profile(
            name: "Persisted",
            curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)]
        )
        try manager.saveCustomProfile(profile)

        let newManager = ProfileManager(storageDirectory: tempDir)
        XCTAssertEqual(newManager.customProfiles.count, 1)
        XCTAssertEqual(newManager.customProfiles[0].name, "Persisted")
    }

    func testDeleteCustomProfile() throws {
        let profile = Profile(
            name: "ToDelete",
            curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)]
        )
        try manager.saveCustomProfile(profile)
        XCTAssertEqual(manager.customProfiles.count, 1)

        try manager.deleteCustomProfile(id: profile.id)
        XCTAssertEqual(manager.customProfiles.count, 0)
    }

    func testDuplicatePreset() throws {
        let preset = manager.presets[0]
        let duplicate = try manager.duplicateAsCustom(preset)
        XCTAssertFalse(duplicate.isPreset)
        XCTAssertEqual(duplicate.curvePoints.count, preset.curvePoints.count)
        XCTAssertTrue(duplicate.name.contains(preset.name))
        XCTAssertEqual(manager.customProfiles.count, 1)
    }

    func testMaxCustomProfiles() throws {
        for i in 0..<10 {
            let p = Profile(
                name: "Profile \(i)",
                curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)]
            )
            try manager.saveCustomProfile(p)
        }
        XCTAssertEqual(manager.customProfiles.count, 10)

        let extra = Profile(
            name: "One Too Many",
            curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)]
        )
        XCTAssertThrowsError(try manager.saveCustomProfile(extra))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodegen generate && xcodebuild test -project Mystral.xcodeproj -scheme MystralTests
```

- [ ] **Step 3: Create preset JSON files**

Create `Mystral/Presets/silent.json`:

```json
{
    "id": "00000000-0000-0000-0000-000000000001",
    "name": "Silent",
    "icon": "speaker.slash",
    "isPreset": true,
    "sensorKey": "",
    "curvePoints": [
        { "temperature": 30, "fanPercentage": 10 },
        { "temperature": 50, "fanPercentage": 20 },
        { "temperature": 70, "fanPercentage": 40 },
        { "temperature": 85, "fanPercentage": 60 },
        { "temperature": 95, "fanPercentage": 80 }
    ]
}
```

Create `Mystral/Presets/balanced.json`:

```json
{
    "id": "00000000-0000-0000-0000-000000000002",
    "name": "Balanced",
    "icon": "dial.medium",
    "isPreset": true,
    "sensorKey": "",
    "curvePoints": [
        { "temperature": 30, "fanPercentage": 15 },
        { "temperature": 50, "fanPercentage": 30 },
        { "temperature": 65, "fanPercentage": 50 },
        { "temperature": 80, "fanPercentage": 75 },
        { "temperature": 95, "fanPercentage": 100 }
    ]
}
```

Create `Mystral/Presets/performance.json`:

```json
{
    "id": "00000000-0000-0000-0000-000000000003",
    "name": "Performance",
    "icon": "hare",
    "isPreset": true,
    "sensorKey": "",
    "curvePoints": [
        { "temperature": 30, "fanPercentage": 25 },
        { "temperature": 45, "fanPercentage": 45 },
        { "temperature": 60, "fanPercentage": 70 },
        { "temperature": 75, "fanPercentage": 90 },
        { "temperature": 85, "fanPercentage": 100 }
    ]
}
```

Create `Mystral/Presets/fullblast.json`:

```json
{
    "id": "00000000-0000-0000-0000-000000000004",
    "name": "Full Blast",
    "icon": "wind",
    "isPreset": true,
    "sensorKey": "",
    "curvePoints": [
        { "temperature": 0, "fanPercentage": 100 }
    ]
}
```

- [ ] **Step 4: Implement ProfileManager.swift**

Create `Mystral/Services/ProfileManager.swift`:

```swift
import Foundation

enum ProfileError: Error, LocalizedError {
    case maxProfilesReached
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .maxProfilesReached: "Maximum of 10 custom profiles reached"
        case .profileNotFound: "Profile not found"
        }
    }
}

@Observable
final class ProfileManager {
    static let maxCustomProfiles = 10

    private(set) var presets: [Profile] = []
    private(set) var customProfiles: [Profile] = []
    var activeProfileId: UUID?

    private let storageDirectory: URL

    var activeProfile: Profile? {
        let all = presets + customProfiles
        return all.first { $0.id == activeProfileId }
    }

    var allProfiles: [Profile] {
        presets + customProfiles
    }

    init(storageDirectory: URL? = nil) {
        let dir = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mystral")
            .appendingPathComponent("profiles")

        self.storageDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        loadPresets()
        loadCustomProfiles()

        if activeProfileId == nil {
            activeProfileId = presets.first { $0.name == "Balanced" }?.id ?? presets.first?.id
        }
    }

    // MARK: - Presets

    private func loadPresets() {
        let presetNames = ["silent", "balanced", "performance", "fullblast"]
        let decoder = JSONDecoder()

        presets = presetNames.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Presets"),
                  let data = try? Data(contentsOf: url),
                  var profile = try? decoder.decode(Profile.self, from: data) else {
                return loadFallbackPreset(name: name)
            }
            profile.isPreset = true
            return profile
        }
    }

    private func loadFallbackPreset(name: String) -> Profile? {
        switch name {
        case "silent":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                           name: "Silent", icon: "speaker.slash", isPreset: true,
                           curvePoints: [
                               CurvePoint(temperature: 30, fanPercentage: 10),
                               CurvePoint(temperature: 50, fanPercentage: 20),
                               CurvePoint(temperature: 70, fanPercentage: 40),
                               CurvePoint(temperature: 85, fanPercentage: 60),
                               CurvePoint(temperature: 95, fanPercentage: 80)
                           ])
        case "balanced":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                           name: "Balanced", icon: "dial.medium", isPreset: true,
                           curvePoints: [
                               CurvePoint(temperature: 30, fanPercentage: 15),
                               CurvePoint(temperature: 50, fanPercentage: 30),
                               CurvePoint(temperature: 65, fanPercentage: 50),
                               CurvePoint(temperature: 80, fanPercentage: 75),
                               CurvePoint(temperature: 95, fanPercentage: 100)
                           ])
        case "performance":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                           name: "Performance", icon: "hare", isPreset: true,
                           curvePoints: [
                               CurvePoint(temperature: 30, fanPercentage: 25),
                               CurvePoint(temperature: 45, fanPercentage: 45),
                               CurvePoint(temperature: 60, fanPercentage: 70),
                               CurvePoint(temperature: 75, fanPercentage: 90),
                               CurvePoint(temperature: 85, fanPercentage: 100)
                           ])
        case "fullblast":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                           name: "Full Blast", icon: "wind", isPreset: true,
                           curvePoints: [CurvePoint(temperature: 0, fanPercentage: 100)])
        default:
            return nil
        }
    }

    // MARK: - Custom Profiles

    private func loadCustomProfiles() {
        let decoder = JSONDecoder()
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        customProfiles = files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let profile = try? decoder.decode(Profile.self, from: data),
                  !profile.isPreset else { return nil }
            return profile
        }
    }

    func saveCustomProfile(_ profile: Profile) throws {
        if let index = customProfiles.firstIndex(where: { $0.id == profile.id }) {
            customProfiles[index] = profile
        } else {
            guard customProfiles.count < Self.maxCustomProfiles else {
                throw ProfileError.maxProfilesReached
            }
            customProfiles.append(profile)
        }
        let data = try JSONEncoder().encode(profile)
        let url = storageDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        try data.write(to: url)
    }

    func deleteCustomProfile(id: UUID) throws {
        guard let index = customProfiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound
        }
        let url = storageDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        customProfiles.remove(at: index)

        if activeProfileId == id {
            activeProfileId = presets.first { $0.name == "Balanced" }?.id
        }
    }

    func duplicateAsCustom(_ preset: Profile) throws -> Profile {
        var copy = preset
        copy = Profile(
            name: "\(preset.name) (Custom)",
            icon: preset.icon,
            isPreset: false,
            curvePoints: preset.curvePoints,
            sensorKey: preset.sensorKey
        )
        try saveCustomProfile(copy)
        return copy
    }
}
```

- [ ] **Step 5: Regenerate and run tests**

```bash
xcodegen generate && xcodebuild test -project Mystral.xcodeproj -scheme MystralTests
```

Expected: ALL TESTS PASSED

- [ ] **Step 6: Commit**

```bash
git add Mystral/Services/ProfileManager.swift Mystral/Presets/ MystralTests/ProfileManagerTests.swift
git commit -m "feat: add ProfileManager with preset profiles and custom profile CRUD"
```

---

### Task 6: Fan Controller & Curve Interpolation

**Files:**
- Create: `Mystral/Services/FanController.swift`
- Create: `MystralTests/CurveInterpolationTests.swift`

- [ ] **Step 1: Write interpolation tests**

Create `MystralTests/CurveInterpolationTests.swift`:

```swift
import XCTest
@testable import Mystral

final class CurveInterpolationTests: XCTestCase {
    let curve: [CurvePoint] = [
        CurvePoint(temperature: 30, fanPercentage: 10),
        CurvePoint(temperature: 50, fanPercentage: 30),
        CurvePoint(temperature: 70, fanPercentage: 60),
        CurvePoint(temperature: 90, fanPercentage: 100)
    ]

    func testExactPoint() {
        XCTAssertEqual(FanController.interpolate(temperature: 50, curve: curve), 30, accuracy: 0.01)
    }

    func testMidpoint() {
        // Between 30°→10% and 50°→30%: midpoint at 40° should be 20%
        XCTAssertEqual(FanController.interpolate(temperature: 40, curve: curve), 20, accuracy: 0.01)
    }

    func testBelowMinimum() {
        XCTAssertEqual(FanController.interpolate(temperature: 10, curve: curve), 10, accuracy: 0.01)
    }

    func testAboveMaximum() {
        XCTAssertEqual(FanController.interpolate(temperature: 100, curve: curve), 100, accuracy: 0.01)
    }

    func testQuarterPoint() {
        // Between 50°→30% and 70°→60%: at 55° = 30 + (5/20)*(60-30) = 37.5%
        XCTAssertEqual(FanController.interpolate(temperature: 55, curve: curve), 37.5, accuracy: 0.01)
    }

    func testSinglePoint() {
        let single = [CurvePoint(temperature: 0, fanPercentage: 100)]
        XCTAssertEqual(FanController.interpolate(temperature: 50, curve: single), 100, accuracy: 0.01)
    }

    func testEmptyCurve() {
        XCTAssertEqual(FanController.interpolate(temperature: 50, curve: []), 0, accuracy: 0.01)
    }

    func testUnsortedCurveStillWorks() {
        let unsorted = [
            CurvePoint(temperature: 70, fanPercentage: 60),
            CurvePoint(temperature: 30, fanPercentage: 10),
            CurvePoint(temperature: 90, fanPercentage: 100),
            CurvePoint(temperature: 50, fanPercentage: 30)
        ]
        XCTAssertEqual(FanController.interpolate(temperature: 40, curve: unsorted), 20, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodegen generate && xcodebuild test -project Mystral.xcodeproj -scheme MystralTests
```

- [ ] **Step 3: Implement FanController.swift**

Create `Mystral/Services/FanController.swift`:

```swift
import Foundation

protocol ProfileActivationStrategy: Sendable {
    func shouldActivate(profile: Profile, sensors: [Sensor]) -> Bool
}

struct ManualActivationStrategy: ProfileActivationStrategy {
    func shouldActivate(profile: Profile, sensors: [Sensor]) -> Bool {
        false
    }
}

@Observable
final class FanController {
    private let smcService: SMCServiceProtocol
    private let profileManager: ProfileManager
    private var timer: Timer?

    private(set) var sensors: [Sensor] = []
    private(set) var fans: [Fan] = []
    private(set) var isRunning = false

    var pollingInterval: TimeInterval = 2.0 {
        didSet {
            if isRunning { restart() }
        }
    }

    var manualOverrides: [Int: Double] = [:]

    init(smcService: SMCServiceProtocol, profileManager: ProfileManager) {
        self.smcService = smcService
        self.profileManager = profileManager
    }

    // MARK: - Interpolation (static for testability)

    static func interpolate(temperature: Double, curve: [CurvePoint]) -> Double {
        guard !curve.isEmpty else { return 0 }

        let sorted = curve.sortedByTemperature()

        if sorted.count == 1 { return sorted[0].fanPercentage }
        if temperature <= sorted[0].temperature { return sorted[0].fanPercentage }
        if temperature >= sorted[sorted.count - 1].temperature { return sorted[sorted.count - 1].fanPercentage }

        for i in 0..<(sorted.count - 1) {
            let low = sorted[i]
            let high = sorted[i + 1]
            if temperature >= low.temperature && temperature <= high.temperature {
                let ratio = (temperature - low.temperature) / (high.temperature - low.temperature)
                return low.fanPercentage + ratio * (high.fanPercentage - low.fanPercentage)
            }
        }

        return sorted[sorted.count - 1].fanPercentage
    }

    // MARK: - Polling

    func start() {
        guard !isRunning else { return }
        isRunning = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        restoreAutoMode()
    }

    func restart() {
        stop()
        start()
    }

    private func tick() {
        do {
            var newSensors = try smcService.getAllSensors()
            for i in newSensors.indices {
                if let existing = sensors.first(where: { $0.id == newSensors[i].id }) {
                    newSensors[i].history = existing.history
                }
                newSensors[i].recordTemperature(newSensors[i].temperature)
            }
            sensors = newSensors
            fans = try smcService.getAllFans()
            applyActiveProfile()
        } catch {
            // SMC read errors are non-fatal; keep running with stale data
        }
    }

    private func applyActiveProfile() {
        guard let profile = profileManager.activeProfile else { return }

        let drivingTemp = resolveDrivingTemperature(for: profile)
        let targetPercentage = Self.interpolate(temperature: drivingTemp, curve: profile.curvePoints)

        for fan in fans {
            let percentage = manualOverrides[fan.id] ?? targetPercentage
            do {
                try smcService.setFanMode(index: fan.id, mode: .forced)
                try smcService.setFanSpeed(index: fan.id, percentage: percentage)
            } catch {
                // Fan write errors are non-fatal; will retry next tick
            }
        }
    }

    private func resolveDrivingTemperature(for profile: Profile) -> Double {
        if !profile.sensorKey.isEmpty,
           let sensor = sensors.first(where: { $0.id == profile.sensorKey }) {
            return sensor.temperature
        }
        let cpuSensors = sensors.filter { $0.id.hasPrefix("Tp") }
        guard !cpuSensors.isEmpty else { return sensors.first?.temperature ?? 0 }
        return cpuSensors.map(\.temperature).reduce(0, +) / Double(cpuSensors.count)
    }

    func clearManualOverride(for fanId: Int) {
        manualOverrides.removeValue(forKey: fanId)
    }

    func clearAllManualOverrides() {
        manualOverrides.removeAll()
    }

    private func restoreAutoMode() {
        for fan in fans {
            try? smcService.setFanMode(index: fan.id, mode: .auto)
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodegen generate && xcodebuild test -project Mystral.xcodeproj -scheme MystralTests
```

Expected: ALL TESTS PASSED

- [ ] **Step 5: Commit**

```bash
git add Mystral/Services/FanController.swift MystralTests/CurveInterpolationTests.swift
git commit -m "feat: add FanController with curve interpolation, polling loop, manual overrides"
```

---

### Task 7: App Shell, AppDelegate & Menu Bar

**Files:**
- Modify: `Mystral/App/MystralApp.swift`
- Create: `Mystral/App/AppDelegate.swift`
- Create: `Mystral/MenuBar/MenuBarManager.swift`

- [ ] **Step 1: Create AppDelegate.swift**

Create `Mystral/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    var menuBarManager: MenuBarManager?
    var fanController: FanController?
    var profileManager: ProfileManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        profileManager = ProfileManager()

        let smcService: SMCServiceProtocol
        do {
            smcService = try SMCService()
        } catch {
            smcService = FallbackSMCService()
        }

        fanController = FanController(smcService: smcService, profileManager: profileManager!)

        menuBarManager = MenuBarManager(
            fanController: fanController!,
            profileManager: profileManager!,
            onOpenWindow: { [weak self] in self?.openMainWindow() }
        )

        fanController!.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        fanController?.stop()
    }

    func openMainWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(activatingAllWindows: true)
            return
        }

        let contentView = MainView(
            fanController: fanController!,
            profileManager: profileManager!
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mystral"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("MystralMainWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(activatingAllWindows: true)

        self.window = window
    }
}

final class FallbackSMCService: SMCServiceProtocol {
    func getAllSensors() throws -> [Sensor] { [] }
    func readTemperature(key: String) throws -> Double { 0 }
    func getAllFans() throws -> [Fan] { [] }
    func readFanSpeed(index: Int) throws -> Int { 0 }
    func setFanSpeed(index: Int, percentage: Double) throws {}
    func setFanMode(index: Int, mode: FanMode) throws {}
}
```

- [ ] **Step 2: Create MenuBarManager.swift**

Create `Mystral/MenuBar/MenuBarManager.swift`:

```swift
import AppKit
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly = "Icon Only"
    case iconAndTemperature = "Icon + Temperature"
    case iconAndRPM = "Icon + RPM"
    case iconAndProfile = "Icon + Profile"
}

@Observable
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let fanController: FanController
    private let profileManager: ProfileManager
    private let onOpenWindow: () -> Void
    private var updateTimer: Timer?

    var displayMode: MenuBarDisplayMode = .iconOnly {
        didSet { updateStatusItem() }
    }

    init(fanController: FanController, profileManager: ProfileManager, onOpenWindow: @escaping () -> Void) {
        self.fanController = fanController
        self.profileManager = profileManager
        self.onOpenWindow = onOpenWindow
        setupStatusItem()
        startUpdating()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "fan", accessibilityDescription: "Mystral")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateStatusItem()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onOpenWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        for profile in profileManager.allProfiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            if profile.id == profileManager.activeProfileId {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Mystral", action: #selector(openApp), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        profileManager.activeProfileId = id
    }

    @objc private func openApp() {
        onOpenWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startUpdating() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        var title = ""
        switch displayMode {
        case .iconOnly:
            break
        case .iconAndTemperature:
            let cpuSensors = fanController.sensors.filter { $0.id.hasPrefix("Tp") }
            if !cpuSensors.isEmpty {
                let avg = cpuSensors.map(\.temperature).reduce(0, +) / Double(cpuSensors.count)
                title = " \(Int(avg))°"
            }
        case .iconAndRPM:
            if let fan = fanController.fans.first {
                title = " \(fan.currentRPM)"
            }
        case .iconAndProfile:
            if let profile = profileManager.activeProfile {
                title = " \(profile.name)"
            }
        }
        button.title = title
    }
}
```

- [ ] **Step 3: Update MystralApp.swift**

Replace `Mystral/App/MystralApp.swift`:

```swift
import SwiftUI

@main
struct MystralApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: Regenerate and build**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Mystral/App/ Mystral/MenuBar/
git commit -m "feat: add app shell with AppDelegate, MenuBarManager, window lifecycle"
```

---

### Task 8: Main View & Sidebar Navigation

**Files:**
- Create: `Mystral/Views/MainView.swift`

- [ ] **Step 1: Create MainView.swift**

Create `Mystral/Views/MainView.swift`:

```swift
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case sensors = "Sensors"
    case fans = "Fans"
    case profiles = "Profiles"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "gauge"
        case .sensors: "thermometer.medium"
        case .fans: "fan"
        case .profiles: "list.bullet"
        case .settings: "gear"
        }
    }

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

struct MainView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var selectedItem: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.localizedName, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Active Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { profileManager.activeProfileId ?? UUID() },
                    set: { profileManager.activeProfileId = $0 }
                )) {
                    ForEach(profileManager.allProfiles) { profile in
                        Label(profile.name, systemImage: profile.icon)
                            .tag(profile.id)
                    }
                }
                .labelsHidden()
            }
            .padding()
        } detail: {
            switch selectedItem {
            case .dashboard:
                DashboardView(fanController: fanController, profileManager: profileManager)
            case .sensors:
                SensorsView(fanController: fanController)
            case .fans:
                FansView(fanController: fanController)
            case .profiles:
                ProfilesView(fanController: fanController, profileManager: profileManager)
            case .settings:
                SettingsView(fanController: fanController, profileManager: profileManager)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
```

- [ ] **Step 2: Create placeholder views so it builds**

Create `Mystral/Views/DashboardView.swift`:

```swift
import SwiftUI

struct DashboardView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    var body: some View {
        Text("Dashboard — TODO")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Mystral/Views/SensorsView.swift`:

```swift
import SwiftUI

struct SensorsView: View {
    let fanController: FanController

    var body: some View {
        Text("Sensors — TODO")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Mystral/Views/FansView.swift`:

```swift
import SwiftUI

struct FansView: View {
    let fanController: FanController

    var body: some View {
        Text("Fans — TODO")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Mystral/Views/ProfilesView.swift`:

```swift
import SwiftUI

struct ProfilesView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    var body: some View {
        Text("Profiles — TODO")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `Mystral/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    var body: some View {
        Text("Settings — TODO")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Mystral/Views/
git commit -m "feat: add main window with NavigationSplitView sidebar and placeholder views"
```

---

### Task 9: Dashboard View

**Files:**
- Modify: `Mystral/Views/DashboardView.swift`

- [ ] **Step 1: Implement DashboardView**

Replace `Mystral/Views/DashboardView.swift`:

```swift
import SwiftUI
import Charts

struct DashboardView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    private var cpuAvgTemp: Double {
        let cpuSensors = fanController.sensors.filter { $0.id.hasPrefix("Tp") }
        guard !cpuSensors.isEmpty else { return 0 }
        return cpuSensors.map(\.temperature).reduce(0, +) / Double(cpuSensors.count)
    }

    private var gpuAvgTemp: Double {
        let gpuSensors = fanController.sensors.filter { $0.id.hasPrefix("Tg") }
        guard !gpuSensors.isEmpty else { return 0 }
        return gpuSensors.map(\.temperature).reduce(0, +) / Double(gpuSensors.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    TemperatureCard(title: "CPU", temperature: cpuAvgTemp)
                    TemperatureCard(title: "GPU", temperature: gpuAvgTemp)
                }

                GroupBox("Fans") {
                    HStack(spacing: 20) {
                        ForEach(fanController.fans) { fan in
                            FanGaugeView(fan: fan)
                        }
                    }
                    .padding()
                }

                GroupBox("Active Profile") {
                    HStack {
                        if let profile = profileManager.activeProfile {
                            Image(systemName: profile.icon)
                                .font(.title2)
                            Text(profile.name)
                                .font(.title3)
                        } else {
                            Text("No profile active")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Profile", selection: Binding(
                            get: { profileManager.activeProfileId ?? UUID() },
                            set: { profileManager.activeProfileId = $0 }
                        )) {
                            ForEach(profileManager.allProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .frame(width: 200)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}

struct TemperatureCard: View {
    let title: String
    let temperature: Double

    private var color: Color {
        switch temperature {
        case ..<50: .green
        case 50..<70: .yellow
        case 70..<85: .orange
        default: .red
        }
    }

    var body: some View {
        GroupBox(title) {
            VStack {
                Text("\(Int(temperature))°C")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                ProgressView(value: min(temperature / 110.0, 1.0))
                    .tint(color)
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
    }
}

struct FanGaugeView: View {
    let fan: Fan

    var body: some View {
        VStack(spacing: 8) {
            Text(fan.name)
                .font(.headline)
            Text("\(fan.currentRPM) RPM")
                .font(.system(size: 24, weight: .medium, design: .rounded))
            ProgressView(value: fan.percentage / 100.0)
                .tint(.blue)
            Text("\(Int(fan.percentage))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
```

- [ ] **Step 3: Commit**

```bash
git add Mystral/Views/DashboardView.swift
git commit -m "feat: implement Dashboard with temperature cards, fan gauges, profile switcher"
```

---

### Task 10: Sensors View

**Files:**
- Modify: `Mystral/Views/SensorsView.swift`

- [ ] **Step 1: Implement SensorsView**

Replace `Mystral/Views/SensorsView.swift`:

```swift
import SwiftUI
import Charts

struct SensorsView: View {
    let fanController: FanController
    @State private var searchText = ""

    private var filteredSensors: [Sensor] {
        if searchText.isEmpty { return fanController.sensors }
        return fanController.sensors.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Table(filteredSensors) {
            TableColumn("Key") { sensor in
                Text(sensor.id)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 60, ideal: 80)

            TableColumn("Name") { sensor in
                Text(sensor.name)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Temperature") { sensor in
                HStack {
                    Text("\(String(format: "%.1f", sensor.temperature))°C")
                        .foregroundStyle(temperatureColor(sensor.temperature))
                        .font(.system(.body, design: .rounded))
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("Trend") { sensor in
                SparklineView(data: sensor.history)
                    .frame(width: 100, height: 24)
            }
            .width(min: 100, ideal: 120)
        }
        .searchable(text: $searchText, prompt: "Filter sensors...")
        .navigationTitle("Sensors (\(fanController.sensors.count))")
    }

    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<50: .green
        case 50..<70: .yellow
        case 70..<85: .orange
        default: .red
        }
    }
}

struct SparklineView: View {
    let data: [Double]

    var body: some View {
        if data.count >= 2 {
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Temp", value)
                    )
                    .foregroundStyle(.blue.gradient)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (data.min() ?? 0 - 5)...(data.max() ?? 100 + 5))
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
git add Mystral/Views/SensorsView.swift
git commit -m "feat: implement Sensors table with sparkline charts and search"
```

---

### Task 11: Fans View

**Files:**
- Modify: `Mystral/Views/FansView.swift`

- [ ] **Step 1: Implement FansView**

Replace `Mystral/Views/FansView.swift`:

```swift
import SwiftUI

struct FansView: View {
    let fanController: FanController

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(fanController.fans) { fan in
                    FanDetailCard(fan: fan, fanController: fanController)
                }

                if fanController.fans.isEmpty {
                    ContentUnavailableView(
                        "No Fans Detected",
                        systemImage: "fan.slash",
                        description: Text("Could not read fan information from SMC.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Fans")
    }
}

struct FanDetailCard: View {
    let fan: Fan
    let fanController: FanController
    @State private var isOverriding = false

    private var overridePercentage: Binding<Double> {
        Binding(
            get: { fanController.manualOverrides[fan.id] ?? fan.percentage },
            set: { fanController.manualOverrides[fan.id] = $0 }
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "fan")
                        .font(.title2)
                        .symbolEffect(.rotate, isActive: fan.currentRPM > 0)
                    Text(fan.name)
                        .font(.title3.bold())
                    Spacer()
                    Text(fan.mode == .forced ? "Forced" : "Auto")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(fan.mode == .forced ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                        .clipShape(Capsule())
                }

                HStack(spacing: 40) {
                    VStack(alignment: .leading) {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(fan.currentRPM) RPM")
                            .font(.system(size: 20, design: .rounded))
                    }
                    VStack(alignment: .leading) {
                        Text("Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(fan.targetRPM) RPM")
                            .font(.system(size: 20, design: .rounded))
                    }
                    VStack(alignment: .leading) {
                        Text("Range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(fan.minRPM)–\(fan.maxRPM) RPM")
                            .font(.system(size: 14, design: .rounded))
                    }
                }

                Divider()

                Toggle("Manual Override", isOn: $isOverriding)
                    .onChange(of: isOverriding) { _, newValue in
                        if !newValue {
                            fanController.clearManualOverride(for: fan.id)
                        }
                    }

                if isOverriding {
                    HStack {
                        Text("\(Int(overridePercentage.wrappedValue))%")
                            .frame(width: 50)
                            .font(.system(.body, design: .rounded))
                        Slider(value: overridePercentage, in: 0...100, step: 5)
                    }
                }
            }
            .padding()
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
git add Mystral/Views/FansView.swift
git commit -m "feat: implement Fans view with RPM display and manual override sliders"
```

---

### Task 12: Profiles View & Curve Editor

**Files:**
- Modify: `Mystral/Views/ProfilesView.swift`
- Create: `Mystral/Views/CurveEditorView.swift`

- [ ] **Step 1: Create CurveEditorView**

Create `Mystral/Views/CurveEditorView.swift`:

```swift
import SwiftUI

struct CurveEditorView: View {
    @Binding var curvePoints: [CurvePoint]
    let sensorKeys: [String]
    @Binding var sensorKey: String

    private let tempRange: ClosedRange<Double> = 0...110
    private let fanRange: ClosedRange<Double> = 0...100

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Driving Sensor")
                    .font(.headline)
                Picker("", selection: $sensorKey) {
                    Text("CPU Average").tag("")
                    ForEach(sensorKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .frame(width: 200)
            }

            HStack(alignment: .top, spacing: 20) {
                curveChart
                    .frame(minWidth: 300, minHeight: 250)
                curveTable
                    .frame(minWidth: 200)
            }
        }
    }

    // MARK: - Chart

    private var curveChart: some View {
        GeometryReader { geometry in
            let sorted = curvePoints.sortedByTemperature()
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                gridLines(width: width, height: height)

                Path { path in
                    guard !sorted.isEmpty else { return }
                    for (index, point) in sorted.enumerated() {
                        let x = xPosition(for: point.temperature, in: width)
                        let y = yPosition(for: point.fanPercentage, in: height)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                ForEach(sorted) { point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .position(
                            x: xPosition(for: point.temperature, in: width),
                            y: yPosition(for: point.fanPercentage, in: height)
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    updatePoint(
                                        id: point.id,
                                        temperature: temperatureFromX(value.location.x, in: width),
                                        fanPercentage: percentageFromY(value.location.y, in: height)
                                    )
                                }
                        )
                }

                // Axis labels
                VStack {
                    Spacer()
                    HStack {
                        Text("0°")
                            .font(.caption2)
                        Spacer()
                        Text("Temperature (°C)")
                            .font(.caption)
                        Spacer()
                        Text("110°")
                            .font(.caption2)
                    }
                }

                HStack {
                    VStack {
                        Text("100%")
                            .font(.caption2)
                        Spacer()
                        Text("Fan")
                            .font(.caption)
                            .rotationEffect(.degrees(-90))
                        Spacer()
                        Text("0%")
                            .font(.caption2)
                    }
                    Spacer()
                }
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func gridLines(width: Double, height: Double) -> some View {
        Canvas { context, size in
            let color = Color.gray.opacity(0.2)
            for temp in stride(from: 0.0, through: 110.0, by: 10.0) {
                let x = xPosition(for: temp, in: width)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    },
                    with: .color(color)
                )
            }
            for pct in stride(from: 0.0, through: 100.0, by: 10.0) {
                let y = yPosition(for: pct, in: height)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    },
                    with: .color(color)
                )
            }
        }
    }

    // MARK: - Table

    private var curveTable: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Temp (°C)")
                    .font(.caption.bold())
                    .frame(width: 80)
                Text("Fan (%)")
                    .font(.caption.bold())
                    .frame(width: 80)
                Spacer()
            }

            ForEach(curvePoints.sortedByTemperature()) { point in
                HStack {
                    TextField("°C", value: Binding(
                        get: { point.temperature },
                        set: { updatePoint(id: point.id, temperature: $0, fanPercentage: nil) }
                    ), format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)

                    TextField("%", value: Binding(
                        get: { point.fanPercentage },
                        set: { updatePoint(id: point.id, temperature: nil, fanPercentage: $0) }
                    ), format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        removePoint(id: point.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(curvePoints.count <= 2)
                }
            }

            Button {
                addPoint()
            } label: {
                Label("Add Point", systemImage: "plus.circle")
            }
            .disabled(curvePoints.count >= 10)
        }
    }

    // MARK: - Coordinate Mapping

    private func xPosition(for temperature: Double, in width: Double) -> Double {
        (temperature - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound) * width
    }

    private func yPosition(for fanPercentage: Double, in height: Double) -> Double {
        height - (fanPercentage - fanRange.lowerBound) / (fanRange.upperBound - fanRange.lowerBound) * height
    }

    private func temperatureFromX(_ x: Double, in width: Double) -> Double {
        let temp = (x / width) * (tempRange.upperBound - tempRange.lowerBound) + tempRange.lowerBound
        return max(tempRange.lowerBound, min(tempRange.upperBound, (temp * 2).rounded() / 2))
    }

    private func percentageFromY(_ y: Double, in height: Double) -> Double {
        let pct = (1 - y / height) * (fanRange.upperBound - fanRange.lowerBound) + fanRange.lowerBound
        return max(fanRange.lowerBound, min(fanRange.upperBound, pct.rounded()))
    }

    // MARK: - Mutations

    private func updatePoint(id: UUID, temperature: Double?, fanPercentage: Double?) {
        guard let index = curvePoints.firstIndex(where: { $0.id == id }) else { return }
        if let temp = temperature {
            curvePoints[index].temperature = max(tempRange.lowerBound, min(tempRange.upperBound, temp))
        }
        if let pct = fanPercentage {
            curvePoints[index].fanPercentage = max(fanRange.lowerBound, min(fanRange.upperBound, pct))
        }
    }

    private func removePoint(id: UUID) {
        guard curvePoints.count > 2 else { return }
        curvePoints.removeAll { $0.id == id }
    }

    private func addPoint() {
        guard curvePoints.count < 10 else { return }
        let sorted = curvePoints.sortedByTemperature()
        let newTemp = (sorted.last?.temperature ?? 50) + 10
        let newPct = (sorted.last?.fanPercentage ?? 50) + 10
        curvePoints.append(CurvePoint(
            temperature: min(newTemp, 110),
            fanPercentage: min(newPct, 100)
        ))
    }
}
```

- [ ] **Step 2: Implement ProfilesView**

Replace `Mystral/Views/ProfilesView.swift`:

```swift
import SwiftUI

struct ProfilesView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var editingProfile: Profile?
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: Profile?

    var body: some View {
        HSplitView {
            profileList
                .frame(minWidth: 220, maxWidth: 300)
            profileDetail
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Profiles")
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    try? profileManager.deleteCustomProfile(id: profile.id)
                    if editingProfile?.id == profile.id { editingProfile = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(profileToDelete?.name ?? "")\"?")
        }
    }

    private var profileList: some View {
        List {
            Section("Presets") {
                ForEach(profileManager.presets) { profile in
                    profileRow(profile, isPreset: true)
                }
            }

            Section("Custom (\(profileManager.customProfiles.count)/\(ProfileManager.maxCustomProfiles))") {
                ForEach(profileManager.customProfiles) { profile in
                    profileRow(profile, isPreset: false)
                }

                if profileManager.customProfiles.count < ProfileManager.maxCustomProfiles {
                    Button {
                        let newProfile = Profile(
                            name: "New Profile",
                            curvePoints: [
                                CurvePoint(temperature: 30, fanPercentage: 15),
                                CurvePoint(temperature: 60, fanPercentage: 50),
                                CurvePoint(temperature: 90, fanPercentage: 100)
                            ]
                        )
                        try? profileManager.saveCustomProfile(newProfile)
                        editingProfile = newProfile
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: Profile, isPreset: Bool) -> some View {
        HStack {
            Image(systemName: profile.icon)
            Text(profile.name)
            Spacer()
            if profile.id == profileManager.activeProfileId {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingProfile = profile
        }
        .contextMenu {
            Button("Activate") {
                profileManager.activeProfileId = profile.id
            }
            if isPreset {
                Button("Duplicate as Custom") {
                    if let copy = try? profileManager.duplicateAsCustom(profile) {
                        editingProfile = copy
                    }
                }
            } else {
                Button("Delete", role: .destructive) {
                    profileToDelete = profile
                    showDeleteConfirmation = true
                }
            }
        }
    }

    private var profileDetail: some View {
        Group {
            if var profile = editingProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !profile.isPreset {
                            HStack {
                                TextField("Profile Name", text: Binding(
                                    get: { profile.name },
                                    set: { newName in
                                        profile.name = newName
                                        editingProfile = profile
                                        try? profileManager.saveCustomProfile(profile)
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                            }
                        } else {
                            HStack {
                                Image(systemName: "lock")
                                Text(profile.name)
                                    .font(.title2.bold())
                                Text("(Preset — read only)")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        CurveEditorView(
                            curvePoints: Binding(
                                get: { profile.curvePoints },
                                set: { newPoints in
                                    profile.curvePoints = newPoints
                                    editingProfile = profile
                                    if !profile.isPreset {
                                        try? profileManager.saveCustomProfile(profile)
                                    }
                                }
                            ),
                            sensorKeys: fanController.sensors.map(\.id),
                            sensorKey: Binding(
                                get: { profile.sensorKey },
                                set: { newKey in
                                    profile.sensorKey = newKey
                                    editingProfile = profile
                                    if !profile.isPreset {
                                        try? profileManager.saveCustomProfile(profile)
                                    }
                                }
                            )
                        )
                        .disabled(profile.isPreset)
                        .opacity(profile.isPreset ? 0.7 : 1.0)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a Profile",
                    systemImage: "list.bullet",
                    description: Text("Choose a profile from the list to view or edit its fan curve.")
                )
            }
        }
    }
}
```

- [ ] **Step 3: Build and commit**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
git add Mystral/Views/CurveEditorView.swift Mystral/Views/ProfilesView.swift
git commit -m "feat: implement Profiles view with curve editor (drag chart + editable table)"
```

---

### Task 13: Settings View

**Files:**
- Modify: `Mystral/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

Replace `Mystral/Views/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var launchAtLogin = false
    @State private var displayMode: MenuBarDisplayMode = .iconOnly
    @State private var pollingInterval: Double = 2.0

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Menu Bar") {
                Picker("Display Mode", selection: $displayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .onChange(of: displayMode) { _, newValue in
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.menuBarManager?.displayMode = newValue
                    }
                    UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarDisplayMode")
                }
            }

            Section("Monitoring") {
                Picker("Polling Interval", selection: $pollingInterval) {
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
                .onChange(of: pollingInterval) { _, newValue in
                    fanController.pollingInterval = newValue
                    UserDefaults.standard.set(newValue, forKey: "pollingInterval")
                }
            }

            Section("Data") {
                Button("Reset All Settings") {
                    resetSettings()
                }
                .foregroundStyle(.red)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                Link("GitHub", destination: URL(string: "https://github.com/fexxdev/Mystral")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let modeStr = UserDefaults.standard.string(forKey: "menuBarDisplayMode"),
           let mode = MenuBarDisplayMode(rawValue: modeStr) {
            displayMode = mode
        }
        let interval = UserDefaults.standard.double(forKey: "pollingInterval")
        if interval > 0 { pollingInterval = interval }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }

    private func resetSettings() {
        setLaunchAtLogin(false)
        launchAtLogin = false
        displayMode = .iconOnly
        pollingInterval = 2.0
        fanController.pollingInterval = 2.0
        fanController.clearAllManualOverrides()
        UserDefaults.standard.removeObject(forKey: "menuBarDisplayMode")
        UserDefaults.standard.removeObject(forKey: "pollingInterval")
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
git add Mystral/Views/SettingsView.swift
git commit -m "feat: implement Settings view with launch-at-login, display mode, polling config"
```

---

### Task 14: Localization (EN + IT)

**Files:**
- Create: `Mystral/Localizable.xcstrings`

- [ ] **Step 1: Create string catalog**

Create `Mystral/Localizable.xcstrings`:

```json
{
  "sourceLanguage": "en",
  "strings": {
    "Dashboard": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Pannello" } }
      }
    },
    "Sensors": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Sensori" } }
      }
    },
    "Fans": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Ventole" } }
      }
    },
    "Profiles": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Profili" } }
      }
    },
    "Settings": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Impostazioni" } }
      }
    },
    "Active Profile": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Profilo Attivo" } }
      }
    },
    "Launch at Login": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Avvia al Login" } }
      }
    },
    "Display Mode": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Modalità Display" } }
      }
    },
    "Polling Interval": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Intervallo Aggiornamento" } }
      }
    },
    "Manual Override": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Override Manuale" } }
      }
    },
    "Add Profile": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Aggiungi Profilo" } }
      }
    },
    "Add Point": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Aggiungi Punto" } }
      }
    },
    "Delete Profile": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Elimina Profilo" } }
      }
    },
    "Reset All Settings": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Ripristina Impostazioni" } }
      }
    },
    "No Fans Detected": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Nessuna Ventola Rilevata" } }
      }
    },
    "Select a Profile": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Seleziona un Profilo" } }
      }
    },
    "General": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Generale" } }
      }
    },
    "Menu Bar": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Barra dei Menu" } }
      }
    },
    "Monitoring": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Monitoraggio" } }
      }
    },
    "About": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Informazioni" } }
      }
    },
    "Driving Sensor": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Sensore Guida" } }
      }
    },
    "CPU Average": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Media CPU" } }
      }
    },
    "Current": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Attuale" } }
      }
    },
    "Target": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Obiettivo" } }
      }
    },
    "Range": {
      "localizations": {
        "it": { "stringUnit": { "state": "translated", "value": "Intervallo" } }
      }
    }
  },
  "version": "1.0"
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build
git add Mystral/Localizable.xcstrings
git commit -m "feat: add EN + IT localization string catalog"
```

---

### Task 15: README & LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

- [ ] **Step 1: Create README.md**

Create `README.md`:

```markdown
# Mystral

A native macOS menu bar app for controlling fan curves on Apple Silicon Macs.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1--M5-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **Menu bar presence** — always-on icon with configurable display (temperature, RPM, profile name)
- **Temperature sensors** — live readings from all SMC temperature sensors with sparkline history
- **Fan monitoring** — real-time RPM, target speed, and per-fan manual override
- **Fan curve editor** — drag-and-drop chart with synchronized editable table
- **Profiles** — 4 built-in presets (Silent, Balanced, Performance, Full Blast) + up to 10 custom profiles
- **Auto-start** — launch at login via macOS native login items
- **Localization** — English and Italian

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1, M2, M3, M4, M5)

## Installation

### Download

Download the latest `.dmg` from [Releases](https://github.com/fexxdev/Mystral/releases).

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/fexxdev/Mystral.git
cd Mystral
xcodegen generate
open Mystral.xcodeproj
```

Build and run in Xcode (⌘R).

## Usage

1. Mystral appears in the menu bar with a fan icon
2. **Left click** the icon to open the main window
3. **Right click** for quick profile switching
4. Go to **Profiles** to create custom fan curves
5. Go to **Settings** to configure auto-start and display options

## Preset Profiles

| Profile | Description |
|---------|-------------|
| Silent | Minimum fan noise, higher temperatures allowed |
| Balanced | Apple-like default curve |
| Performance | Aggressive cooling for heavy workloads |
| Full Blast | All fans at maximum speed |

## Privacy

Mystral runs entirely offline. No telemetry, no network access, no data collection.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Create LICENSE**

Create `LICENSE`:

```
MIT License

Copyright (c) 2026 fexxdev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Commit**

```bash
git add README.md LICENSE
git commit -m "docs: add README and MIT license"
```

---

### Task 16: First Push & Verify

- [ ] **Step 1: Push to GitHub**

```bash
git push -u origin main
```

- [ ] **Step 2: Verify build compiles cleanly**

```bash
xcodegen generate && xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -project Mystral.xcodeproj -scheme MystralTests -configuration Debug 2>&1 | tail -10
```

Expected: All tests pass.
