//
//  Nothing_X_MacOSApp.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 07/01/23.
//

import SwiftUI


@main
struct Nothing_X_MacOSApp: App {
    @StateObject private var store = Store()
    @StateObject private var viewModel = MainViewViewModel(bluetoothService: BluetoothServiceImpl(), nothingRepository: NothingRepositoryImpl.shared, nothingService: NothingServiceImpl.shared)

    private var batteryText: String {
        let left = viewModel.leftBattery.map(Int.init)
        let right = viewModel.rightBattery.map(Int.init)

        // With one bud in the case or powered off only one side reports —
        // show what's available instead of nothing
        switch (left, right) {
        case (nil, nil):
            return ""
        case (let l?, nil):
            return "\(l)%"
        case (nil, let r?):
            return "\(r)%"
        case (let l?, let r?):
            switch store.batteryDisplayMode {
            case .both:
                return l == r ? "\(l)%" : "\(l)·\(r)%"
            case .average:
                return "\((l + r) / 2)%"
            case .minimum:
                return "\(min(l, r))%"
            }
        }
    }

    /// Earbud icon for earbuds (and before anything connects), a headphone
    /// glyph for over-ear models and the neckband
    @ViewBuilder
    private var menuBarLabel: some View {
        switch viewModel.nothingDevice?.codename.form {
        case .headphones?, .neckband?:
            Label(batteryText, systemImage: "headphones")
                .labelStyle(.titleAndIcon)
        default:
            Label(batteryText, image: "nothing.ear.1")
                .labelStyle(.titleAndIcon)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            NXQuickPanel()
                .environmentObject(store)
                .environmentObject(viewModel)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Window("Nothing X", id: "nothing-x") {
            NXWindowView()
                .environmentObject(store)
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
