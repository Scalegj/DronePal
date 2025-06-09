import SwiftUI

// This file contains all views related to managing Checklists.

struct ChecklistListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showAddChecklistSheet = false

    var body: some View {
        Group {
            if viewModel.checklists.isEmpty {
                ContentUnavailableView(
                    "No Checklists",
                    systemImage: "checklist",
                    description: Text("Tap the + button to create your first pre-flight checklist.")
                )
            } else {
                List {
                    ForEach(viewModel.checklists) { checklist in
                        NavigationLink(destination: ChecklistDetailView(checklist: checklist)) {
                            VStack(alignment: .leading) {
                                Text(checklist.name).font(.headline)
                                Text("\(checklist.items.count) items").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: viewModel.deleteChecklist)
                }
            }
        }
        .navigationTitle("Pre-flight Checklists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddChecklistSheet.toggle() }) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
            }
        }
        .sheet(isPresented: $showAddChecklistSheet) {
            AddEditChecklistView(checklistToEdit: nil)
        }
    }
}

struct AddEditChecklistView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var checklist: Checklist
    let isEditing: Bool

    init(checklistToEdit: Checklist?) {
        if let existingChecklist = checklistToEdit {
            _checklist = State(initialValue: existingChecklist)
            isEditing = true
        } else {
            _checklist = State(initialValue: Checklist(id: UUID(), name: "", items: []))
            isEditing = false
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Checklist Details") {
                    TextField("Checklist Name", text: $checklist.name)
                }
                Section("Checklist Items") {
                    ForEach($checklist.items) { $item in
                        TextField("Checklist item", text: $item.text)
                    }
                    .onDelete { offsets in
                        checklist.items.remove(atOffsets: offsets)
                    }
                    Button("Add Item", systemImage: "plus") {
                        checklist.items.append(ChecklistItem(id: UUID(), text: ""))
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Checklist" : "Add Checklist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var checklistToSave = checklist
                        checklistToSave.items.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                        viewModel.saveChecklist(checklistToSave)
                        dismiss()
                    }
                    .disabled(checklist.name.isEmpty)
                }
            }
        }
    }
}

struct ChecklistDetailView: View {
    let checklist: Checklist
    @State private var showEditSheet = false

    var body: some View {
        Form {
            Section("Checklist Items") {
                if checklist.items.isEmpty {
                    Text("No items in this checklist.")
                } else {
                    ForEach(checklist.items) { item in
                        Text(item.text)
                    }
                }
            }
        }
        .navigationTitle(checklist.name)
        .toolbar {
            Button("Edit") { showEditSheet.toggle() }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditChecklistView(checklistToEdit: checklist)
        }
    }
}
