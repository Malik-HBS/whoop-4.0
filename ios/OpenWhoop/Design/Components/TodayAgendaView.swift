import SwiftUI

struct TodayAgendaView: View {
    private struct TodoItem: Identifiable {
        let id = UUID()
        var text: String
        var isDone: Bool
    }

    // TODO: Add persistence later if agenda items should survive app relaunches.
    @State private var todos: [TodoItem] = [
        TodoItem(text: "Review recovery trend", isDone: false),
        TodoItem(text: "Hydrate before training", isDone: false)
    ]
    @State private var newTodoText = ""

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: WH.Spacing.md) {
                HStack {
                    Text("TODAY'S AGENDA")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)

                    Spacer()

                    Button {
                        addTodo()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedNewTodo.isEmpty)
                    .opacity(trimmedNewTodo.isEmpty ? 0.45 : 1)
                }

                VStack(spacing: 12) {
                    ForEach($todos) { $todo in
                        Button {
                            todo.isDone.toggle()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(todo.isDone ? WH.Color.recoveryGreen : WH.Color.textSecondary)

                                Text(todo.text)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(todo.isDone ? WH.Color.textSecondary : WH.Color.textPrimary.opacity(0.88))
                                    .strikethrough(todo.isDone, color: WH.Color.textSecondary)

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)

                    TextField("Add a task...", text: $newTodoText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WH.Color.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(addTodo)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(hex: "#15171B"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "#2A2D33"), lineWidth: 1)
                }
            }
        }
    }

    private var trimmedNewTodo: String {
        newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTodo() {
        let text = trimmedNewTodo
        guard !text.isEmpty else { return }
        todos.append(TodoItem(text: text, isDone: false))
        newTodoText = ""
    }
}

