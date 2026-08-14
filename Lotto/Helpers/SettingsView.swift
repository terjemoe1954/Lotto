//
//  SettingsView.swift
//  Lotto
//
//  Created by Terje Moe on 12/02/2026.
//

import SwiftUI
import SwiftData

/// App settings (dark mode and prediction tolerance).
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var toleranse: Double
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Settings")
                    .font(.system(size: 20, weight: .semibold))){
                        Section(header: Text("Modus"),
                                footer: Text("")) {
                            Toggle(isOn: $darkModeEnabled) {
                                Text(!darkModeEnabled ? "Dag modus" : "Natt modus")
                            }
                            
                           Section(header: Text("Prediction Toleranse 0 = Ingen")
                                .font(.system(size: 20, weight: .semibold))){
                                    HStack {
                                        Text("Dager:")
                                        TextField("Beløp :", value: $toleranse, formatter: NumberFormatter())
                             }
                        }
                    }
                }
            }
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction){
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            
        } .preferredColorScheme(darkModeEnabled ? .dark : .light)
    }
}

#Preview {
    SettingsView(toleranse: .constant(4.0))
}
