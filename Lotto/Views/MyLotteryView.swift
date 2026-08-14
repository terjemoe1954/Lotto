//
//  MyLotteryView.swift
//  Lotto
//
//  Created by Terje Moe on 04/02/2026.
//

import SwiftUI
import SwiftData

/// Shared style for number text fields in the submission form.
struct NumberFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
            .font(.system(.body, design: .rounded))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .monospacedDigit()
    }
}

extension View {
    /// Apply NumberFieldStyle to number fields.
    func numberFieldStyle() -> some View {
        self.modifier(NumberFieldStyle())
    }
}


/// Form for registering the user's own rows.
struct MyLotteryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Result.dato, order: .forward) private var results: [Result]
    @Environment(\.dismiss) var dismiss
    @State private var result: Result = Result()
    
    @State private var nr1Text: String = ""
    @State private var nr2Text: String = ""
    @State private var nr3Text: String = ""
    @State private var nr4Text: String = ""
    @State private var nr5Text: String = ""
    @State private var nr6Text: String = ""
    @State private var nr7Text: String = ""
    
    private enum Field: Hashable { case nr1, nr2, nr3, nr4, nr5, nr6, nr7 }
    @FocusState private var focusedField: Field?
    
    var body: some View {
        ZStack {
            Form {
                Button("Tilbake") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                VStack(alignment:.center) {
                    
                    DatePicker("Treknings Dato", selection: $result.dato, displayedComponents: .date)
                        .padding(36)
                    
                    VStack(alignment: .center, spacing: 20) {
                        Group {
                            Text("Registrer din rekke her")
                                .font(.headline).foregroundStyle(.black)
                            TextField("1", text: $nr1Text)
                                .keyboardType(.numberPad)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .nr1)
                                .onChange(of: nr1Text) { nr1Text = nr1Text.filter { $0.isNumber } }
                                .onSubmit { focusedField = .nr2 }
                                .numberFieldStyle()
                                .frame(width: 60)
                        }
                        
                        TextField("2", text: $nr2Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr2)
                            .onChange(of: nr2Text) { nr2Text = nr2Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = .nr3 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("3", text: $nr3Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr3)
                            .onChange(of: nr3Text) { nr3Text = nr3Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = .nr4 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("4", text: $nr4Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr4)
                            .onChange(of: nr4Text) { nr4Text = nr4Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = .nr5 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("5", text: $nr5Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr5)
                            .onChange(of: nr5Text) { nr5Text = nr5Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = .nr6 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("6", text: $nr6Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr6)
                            .onChange(of: nr6Text) { nr6Text = nr6Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = .nr7 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("7", text: $nr7Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .nr7)
                            .onChange(of: nr7Text) { nr7Text = nr7Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = nil }
                            .numberFieldStyle()
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 4)
                    
                    Button("Lagre Ny Rekke") {
                        // Parse inputs from the text fields.
                        let n1 = Int(nr1Text) ?? 0
                        let n2 = Int(nr2Text) ?? 0
                        let n3 = Int(nr3Text) ?? 0
                        let n4 = Int(nr4Text) ?? 0
                        let n5 = Int(nr5Text) ?? 0
                        let n6 = Int(nr6Text) ?? 0
                        let n7 = Int(nr7Text) ?? 0
                        
                        // Assign to model.
                        result.nr1 = n1
                        result.nr2 = n2
                        result.nr3 = n3
                        result.nr4 = n4
                        result.nr5 = n5
                        result.nr6 = n6
                        result.nr7 = n7
                        
                        result.weekNr = getWeekNumber(from: result.dato)
                        context.insert(result)
                        do {
                            try context.save()
                            // Reset form for a new entry, keep the date.
                            let currentDate = result.dato
                            result = Result()
                            result.dato = currentDate
                            nr1Text = ""
                            nr2Text = ""
                            nr3Text = ""
                            nr4Text = ""
                            nr5Text = ""
                            nr6Text = ""
                            nr7Text = ""
                            focusedField = .nr1
                        } catch {
                            print("Save failed:", error.localizedDescription)
                        }
                    }
                    .disabled({
                        let values = [nr1Text, nr2Text, nr3Text, nr4Text, nr5Text, nr6Text, nr7Text].compactMap { Int($0) }
                        let allValid = values.count == 7 && values.allSatisfy { $0 >= 1 }
                        return !allValid || !result.dato.isSaturday
                    }())
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 20)
                    
                }
            }
            
        }
        .onAppear {
            // Initialize a fresh result when the view appears
            result = Result()
            nr1Text = ""
            nr2Text = ""
            nr3Text = ""
            nr4Text = ""
            nr5Text = ""
            nr6Text = ""
            nr7Text = ""
            focusedField = .nr1
        }
        .background(Color.blue)
        
    }
    
    /// Returns the week number (1-53) for the given date.
    func getWeekNumber(from date: Date) -> Int {
        // Use current calendar,, or specify for consistent results
        let calendar = Calendar.current
        // Returns 1-53
        return calendar.component(.weekOfYear, from: date)
    }
}
