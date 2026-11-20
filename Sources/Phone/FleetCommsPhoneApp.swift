//  FleetCommsPhoneApp.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import SwiftUI

@main
struct FleetCommsPhoneApp: App {
    @State private var model = PhoneModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HandsetView(model: model)
                .preferredColorScheme(.dark)
                .onAppear { model.appBecameActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.appBecameActive()
            }
        }
    }
}
