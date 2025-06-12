//
//  SnapFocusApp.swift
//  SnapFocus
//
//  Created by Ahmed Alqurashi on 31/05/2025.
//

import SwiftUI

@main
struct SnapFocusApp: App {
    @StateObject var timerStore = TimerStore()
    @Environment(\.scenePhase) private var phase
    init() {
        // Force selectedDate to today on launch
        let today = Calendar.current.startOfDay(for: Date())
        timerStore.selectedDate = today
    }
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(timerStore)
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .background {
                timerStore.save() // just persist state – do NOT close the bucket
            }
        }
    }
}
