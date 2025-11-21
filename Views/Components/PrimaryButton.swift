import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    init(title: String, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDisabled = isDisabled
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isDisabled ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
    }
}
