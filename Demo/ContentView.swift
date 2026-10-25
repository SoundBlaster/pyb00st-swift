import SwiftUI
import pyb00st

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = DemoSession()
    @State private var speed = 30.0

    private var controlsDisabled: Bool {
        !session.isConnected || session.isConnecting || session.isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") {
                        if session.isConnecting {
                            ProgressView().controlSize(.small)
                            Text("Connecting…")
                        } else if session.isConnected {
                            Text(session.deviceName ?? "Connected")
                        } else {
                            Text("Disconnected").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        session.shouldConnect.toggle()
                    } label: {
                        if session.isConnecting {
                            Text("Cancel connection")
                        } else if session.isConnected {
                            Text("Disconnect")
                        } else {
                            Text("Connect")
                        }
                    }
                    .accessibilityIdentifier("connect")
                } header: {
                    Text("Move Hub")
                } footer: {
                    Text("Press the hub’s green button, then Connect. The first nearby BOOST hub is selected.")
                }

                Section("Hub light") {
                    HStack {
                        Button("Green") { Task { await session.setColor(.green) } }
                        Button("Blue") { Task { await session.setColor(.blue) } }
                        Button("Red") { Task { await session.setColor(.red) } }
                        Button("Off") { Task { await session.setColor(.off) } }
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(controlsDisabled)

                Section {
                    VStack(alignment: .leading) {
                        Text("Speed: \(Int(speed))%")
                            .monospacedDigit()
                        Slider(value: $speed, in: -50...50, step: 10) {
                            Text("Motor speed")
                        }
                        .labelsHidden()
                        .accessibilityLabel("Motor speed")
                        .accessibilityValue("\(Int(speed)) percent")
                    }
                    HStack {
                        Button("Run A") { Task { await session.runMotor(.a, speed: Int(speed)) } }
                            .accessibilityIdentifier("motor-a")
                        Button("Run B") { Task { await session.runMotor(.b, speed: Int(speed)) } }
                            .accessibilityIdentifier("motor-b")
                        Button("Run A + B") { Task { await session.runPair(speed: Int(speed)) } }
                            .accessibilityIdentifier("motor-pair")
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Motors · 500 ms")
                } footer: {
                    Text("Negative speed reverses direction. Keep the hub clear to move.")
                }
                .disabled(controlsDisabled)

                SensorReadings(values: session.values)

                if let error = session.errorMessage {
                    Section("Error") {
                        Text(error).foregroundStyle(.red)
                        Button("Dismiss") { session.errorMessage = nil }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Move Hub Demo")
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 600, idealHeight: 680)
        #endif
        .task(id: session.shouldConnect) {
            if session.shouldConnect { await session.connect() }
            else { session.disconnect() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.disconnect() }
        }
        .onDisappear { session.disconnect() }
    }
}

private struct SensorReadings: View {
    let values: HubValues

    var body: some View {
        Section("Sensors") {
            LabeledContent("Button") {
                if let pressed = values.isButtonPressed {
                    if pressed { Text("Pressed") }
                    else { Text("Released") }
                } else {
                    Text("—")
                }
            }
            .accessibilityElement(children: .combine)
            LabeledContent("Tilt", value: values.tilt.map { String(describing: $0) } ?? "—")
                .accessibilityElement(children: .combine)
            LabeledContent("Encoder A", value: values.ports[.a]?.angle.map { "\($0)°" } ?? "—")
                .accessibilityElement(children: .combine)
            LabeledContent("Encoder B", value: values.ports[.b]?.angle.map { "\($0)°" } ?? "—")
                .accessibilityElement(children: .combine)
        }
        .monospacedDigit()
    }
}

#Preview {
    ContentView()
}
