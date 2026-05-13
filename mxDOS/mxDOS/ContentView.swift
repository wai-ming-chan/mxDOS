//
//  ContentView.swift
//  mxDOS
//

import SwiftUI

struct ContentView: View {
    private let bridge = DOSBoxBridge()
    @State private var launched = false

    private var configURL: URL {
        // dosbox.conf is bundled in the app; at runtime it lives in the
        // app's Documents folder so DOSBox can write its files there.
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        return docs.appendingPathComponent("dosbox.conf")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("mxDOS")
                .font(.largeTitle)
                .bold()

            if !launched {
                Button("Launch DOSBox") {
                    launched = true
                    bridge.start(withConfig: configURL.path)
                }
                .buttonStyle(.borderedProminent)
                .font(.title2)
            } else {
                Text("DOSBox running…")
                    .foregroundColor(.secondary)

                Button("Quit") {
                    bridge.stop()
                    launched = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            copyDefaultConfigIfNeeded()
        }
    }

    private func copyDefaultConfigIfNeeded() {
        let dest = configURL
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        if let src = Bundle.main.url(forResource: "dosbox", withExtension: "conf") {
            try? FileManager.default.copyItem(at: src, to: dest)
        }
    }
}

#Preview {
    ContentView()
}
