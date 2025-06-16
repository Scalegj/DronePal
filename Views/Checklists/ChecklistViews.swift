import SwiftUI

struct ChecklistListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showAddChecklistSheet = false
    
    private var sortedChecklists: [Checklist] {
        viewModel.checklists.sorted { $0.isFavorite && !$1.isFavorite }
    }

    var body: some View {
        VStack(spacing: 0) {
            ChecklistSummaryView()
                .padding()

            if viewModel.checklists.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView("No Checklists", systemImage: "checklist", description: Text("Tap the + button to create your first pre-flight checklist."))
                        .frame(maxHeight: .infinity)
                } else {
                    LegacyContentUnavailableView {
                        Label("No Checklists", systemImage: "checklist")
                    } description: {
                        Text("Tap the + button to create your first pre-flight checklist.")
                    }
                }
            } else {
                List {
                    ForEach(sortedChecklists) { checklist in
                        ChecklistRowView(checklist: checklist)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .onDelete(perform: viewModel.deleteChecklist)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
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

struct ChecklistSummaryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // FIXED: Added the missing 'image' parameter with a relevant SF Symbol.
            StatBox(title: "Total Checklists", value: "\(viewModel.checklists.count)", image: "doc.text.magnifyingglass", color: .indigo)
        }
        .frame(maxHeight: 100)
    }
}

struct ChecklistRowView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let checklist: Checklist
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    viewModel.toggleFavorite(for: checklist)
                }
            }) {
                Image(systemName: checklist.isFavorite ? "star.fill" : "star")
                    .font(.title) // MODIFICATION: Larger icon
                    .foregroundColor(.yellow)
                    .scaleEffect(checklist.isFavorite ? 1.2 : 1.0) // MODIFICATION: Animation effect
            }
            .buttonStyle(.plain)

            NavigationLink(destination: ChecklistDetailView(checklist: checklist)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(checklist.name)
                            .font(.headline.bold())
                        Text("\(checklist.items.count) items")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
        .foregroundColor(.white)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.indigo, .purple.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .indigo.opacity(0.3), radius: 8, x: 0, y: 4)
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
