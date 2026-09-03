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
    let initialDrawDate: Date?
    let initialNumbers: [Int]?
    
    @State private var nr1Text: String = ""
    @State private var nr2Text: String = ""
    @State private var nr3Text: String = ""
    @State private var nr4Text: String = ""
    @State private var nr5Text: String = ""
    @State private var nr6Text: String = ""
    @State private var nr7Text: String = ""
    
    private enum Field: Hashable { case nr1, nr2, nr3, nr4, nr5, nr6, nr7 }
    @FocusState private var focusedField: Field?
    @State private var errorMessage: String?

    private var enteredNumbers: [Int] {
        [nr1Text, nr2Text, nr3Text, nr4Text, nr5Text, nr6Text, nr7Text]
            .compactMap(Int.init)
    }

    private var hasDuplicateNumbers: Bool {
        enteredNumbers.count != Set(enteredNumbers).count
    }

    private var canSaveRow: Bool {
        enteredNumbers.count == 7 && validationMessage == nil
    }

    private var validationMessage: String? {
        LottoRules.rowValidationMessage(numbers: enteredNumbers, drawDate: result.dato)
            ?? LottoRules.duplicateResultValidationMessage(
                numbers: enteredNumbers,
                drawDate: result.dato,
                existingResults: results
            )
    }

    init(initialDrawDate: Date? = nil, initialNumbers: [Int]? = nil) {
        self.initialDrawDate = initialDrawDate
        self.initialNumbers = initialNumbers
    }
    
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

                    Text("Kun lordager kan brukes. Andre datoer flyttes til neste lordag.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .center, spacing: 20) {
                        Group {
                            Text("Registrer din rekke her")
                                .font(.headline).foregroundStyle(.black)
                            TextField("1", text: $nr1Text)
                                .keyboardType(.numberPad)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .nr1)
                                .onChange(of: nr1Text) { sanitizeNumberInput(&nr1Text) }
                                .onSubmit { focusedField = .nr2 }
                                .numberFieldStyle()
                                .frame(width: 60)
                        }
                        
                        TextField("2", text: $nr2Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr2)
                            .onChange(of: nr2Text) { sanitizeNumberInput(&nr2Text) }
                            .onSubmit { focusedField = .nr3 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("3", text: $nr3Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr3)
                            .onChange(of: nr3Text) { sanitizeNumberInput(&nr3Text) }
                            .onSubmit { focusedField = .nr4 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("4", text: $nr4Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr4)
                            .onChange(of: nr4Text) { sanitizeNumberInput(&nr4Text) }
                            .onSubmit { focusedField = .nr5 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("5", text: $nr5Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr5)
                            .onChange(of: nr5Text) { sanitizeNumberInput(&nr5Text) }
                            .onSubmit { focusedField = .nr6 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("6", text: $nr6Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .nr6)
                            .onChange(of: nr6Text) { sanitizeNumberInput(&nr6Text) }
                            .onSubmit { focusedField = .nr7 }
                            .numberFieldStyle()
                            .frame(width: 60)
                        
                        TextField("7", text: $nr7Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .nr7)
                            .onChange(of: nr7Text) { sanitizeNumberInput(&nr7Text) }
                            .onSubmit { focusedField = nil }
                            .numberFieldStyle()
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 4)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button("Lagre Ny Rekke") {
                        guard canSaveRow else {
                            return
                        }

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
                            errorMessage = "Kunne ikke lagre rekken: \(error.localizedDescription)"
                        }
                    }
                    .disabled(!canSaveRow)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 20)
                    
                }
            }
            
        }
        .onAppear {
            configureInitialState()
        }
        .onChange(of: result.dato) { _, _ in
            enforceSaturdaySelection()
        }
        .background(Color.blue)
        .alert("Feil", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        
    }
    
    /// Returns the week number (1-53) for the given date.
    func getWeekNumber(from date: Date) -> Int {
        LottoDateSupport.weekNumber(for: date)
    }

    private func sanitizeNumberInput(_ text: inout String) {
        text = LottoRules.sanitizeNumberInput(text)
    }

    private func configureInitialState() {
        result = Result()
        result.dato = LottoDateSupport.nextSaturday(onOrAfter: initialDrawDate ?? .now)

        let numbers = Array((initialNumbers ?? []).prefix(7))
        nr1Text = numbers.indices.contains(0) ? String(numbers[0]) : ""
        nr2Text = numbers.indices.contains(1) ? String(numbers[1]) : ""
        nr3Text = numbers.indices.contains(2) ? String(numbers[2]) : ""
        nr4Text = numbers.indices.contains(3) ? String(numbers[3]) : ""
        nr5Text = numbers.indices.contains(4) ? String(numbers[4]) : ""
        nr6Text = numbers.indices.contains(5) ? String(numbers[5]) : ""
        nr7Text = numbers.indices.contains(6) ? String(numbers[6]) : ""
        focusedField = numbers.isEmpty ? .nr1 : nil
    }

    private func enforceSaturdaySelection() {
        let saturday = LottoDateSupport.nextSaturday(onOrAfter: result.dato)
        if saturday != LottoDateSupport.normalize(result.dato) {
            result.dato = saturday
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }
}
