//
//  NewJackpotView.swift
//  Lotto
// ny
//  Created by Terje Moe on 02/02/2026.
//

import SwiftUI
import SwiftData

/// Form for registering new jackpot draws.
struct NewJackpotView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JackPot.dato, order: .forward) private var jackpots: [JackPot]
    @Environment(\.dismiss) var dismiss
    @State private var nr1Text: String = ""
    @State private var nr2Text: String = ""
    @State private var nr3Text: String = ""
    @State private var nr4Text: String = ""
    @State private var nr5Text: String = ""
    @State private var nr6Text: String = ""
    @State private var nr7Text: String = ""
    @State private var nr8Text: String = ""
    
    private enum Field: Hashable { case nr1, nr2, nr3, nr4, nr5, nr6, nr7 , nr8}
    @FocusState private var focusedField: Field?
    
    @State private var jackpot: JackPot = JackPot(
        dato: Date(),
        nr1: 0, nr2: 0, nr3: 0, nr4: 0,
        nr5: 0, nr6: 0, nr7: 0, nr8: 0,
        weekNr: 0
    )
    
    private var intFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }
    
    var body: some View {
        ZStack {
            Form {
                HStack {
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Slett all poster") {
                        do {
                            try deleteAll(of: JackPot.self, in: context)
                        } catch {
                            // TODO: show an error to the user.
                        }
                    }
                    .foregroundStyle(.red)
                    .tint(.yellow)
                    .buttonStyle(.borderedProminent)
                    
                }
                
                
                VStack(alignment:.center) {
                    
                    DatePicker("Trekningsdato", selection: $jackpot.dato, displayedComponents: .date)
                        .padding(36)
                    VStack {
                        Group {
                            Text("Registrer Vinnertall Her")
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
                        
                        TextField("8", text: $nr8Text)
                            .keyboardType(.numberPad)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .nr8)
                            .onChange(of: nr8Text) { nr8Text = nr8Text.filter { $0.isNumber } }
                            .onSubmit { focusedField = nil }
                            .numberFieldStyle()
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 4)
                    
                    Button("Save jackpot") {
                        jackpot.weekNr = getWeekNumber(from: jackpot.dato)
                        // Parse inputs from the text fields.
                        let n1 = Int(nr1Text) ?? 0
                        let n2 = Int(nr2Text) ?? 0
                        let n3 = Int(nr3Text) ?? 0
                        let n4 = Int(nr4Text) ?? 0
                        let n5 = Int(nr5Text) ?? 0
                        let n6 = Int(nr6Text) ?? 0
                        let n7 = Int(nr7Text) ?? 0
                        let n8 = Int(nr8Text) ?? 0
                        
                        // Assign to model.
                        jackpot.nr1 = n1
                        jackpot.nr2 = n2
                        jackpot.nr3 = n3
                        jackpot.nr4 = n4
                        jackpot.nr5 = n5
                        jackpot.nr6 = n6
                        jackpot.nr7 = n7
                        jackpot.nr8 = n8
                        jackpot.weekNr = getWeekNumber(from: jackpot.dato)
                        context.insert(jackpot)
                        do {
                            try context.save()
                            // Reset form for a new entry, keep the date.
                            let currentDate = jackpot.dato
                            jackpot = JackPot()
                            jackpot.dato = currentDate
                            nr1Text = ""
                            nr2Text = ""
                            nr3Text = ""
                            nr4Text = ""
                            nr5Text = ""
                            nr6Text = ""
                            nr7Text = ""
                            nr8Text = ""
                            focusedField = .nr1
                        } catch {
                            print("Save failed:", error.localizedDescription)
                        }
                    }
                    .disabled({
                        let values = [nr1Text, nr2Text, nr3Text, nr4Text, nr5Text, nr6Text, nr7Text, nr8Text].compactMap { Int($0) }
                        let allValid = values.count == 8 && values.allSatisfy { $0 >= 1 }
                        return !allValid || !jackpot.dato.isSaturday
                    }())
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 20)
                }
            }
            
        }
        .onAppear {
            // Initialize a fresh result when the view appears
            jackpot = JackPot()
            nr1Text = ""
            nr2Text = ""
            nr3Text = ""
            nr4Text = ""
            nr5Text = ""
            nr6Text = ""
            nr7Text = ""
            nr8Text = ""
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
    
    /// Deletes all rows of a given model type.
    func deleteAll<MyModel: PersistentModel>(
        of type: MyModel.Type,
        in context: ModelContext
    ) throws {
        try context.delete(model: MyModel.self) // Predicate = nil deletes all rows of this type.
        try context.save()
    }
}


extension Date {
    /// Returns true when the date is a Saturday.
    var isSaturday: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday], from: self)
        return components.weekday == 7  // Sunday=1, Monday=2, ..., Saturday=7
    }
}
