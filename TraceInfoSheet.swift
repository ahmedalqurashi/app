import SwiftUI

struct TraceInfoSheet: View {
    @State var trace: TimeTrace
    let onDelete: () -> Void
    let onUpdate: (TimeTrace) -> Void
    let onClose: () -> Void
    
    @State private var editedLabel: String
    @State private var editedStart: Date
    @State private var editedEnd: Date
    
    init(trace: TimeTrace, onDelete: @escaping () -> Void, onUpdate: @escaping (TimeTrace) -> Void, onClose: @escaping () -> Void) {
        self._trace = State(initialValue: trace)
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self.onClose = onClose
        self._editedLabel = State(initialValue: trace.label)
        self._editedStart = State(initialValue: trace.start)
        self._editedEnd = State(initialValue: trace.end)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Trace Info")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.title2)
                        .padding(8)
                        .background(Color(.systemGray6).opacity(0.18))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("Date: ")
                        .foregroundColor(.gray)
                    Text(formattedDate(editedStart))
                        .foregroundColor(.white)
                }
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.purple)
                    Text("Time: ")
                        .foregroundColor(.gray)
                    DatePicker("Start", selection: $editedStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxWidth: 120)
                    Text("-")
                        .foregroundColor(.gray)
                    DatePicker("End", selection: $editedEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxWidth: 120)
                }
                HStack(alignment: .top) {
                    Image(systemName: "pencil")
                        .foregroundColor(.green)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What was done:")
                            .foregroundColor(.gray)
                        TextField("Label", text: $editedLabel)
                            .foregroundColor(.white)
                            .font(.body)
                            .padding(10)
                            .background(Color(.systemGray6).opacity(0.18))
                            .cornerRadius(10)
                    }
                }
            }
            .font(.body)
            .padding(.horizontal)
            Spacer()
            Button(action: {
                var updated = trace
                updated.label = editedLabel
                updated.start = editedStart
                updated.end = editedEnd
                onUpdate(updated)
            }) {
                Text("Save")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal)
            Button(action: onClose) {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6).opacity(0.18))
                    .cornerRadius(16)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
    func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
} 