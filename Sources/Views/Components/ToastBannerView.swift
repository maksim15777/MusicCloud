import SwiftUI

public struct ToastBannerView: View {
    public let toast: ToastMessage
    public let onDismiss: () -> Void
    
    public var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(toast.isError ? Color.red.opacity(0.2) : Color.white.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: toast.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(toast.isError ? .red : .white)
            }
            
            // Text Content
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let msg = toast.message, !msg.isEmpty {
                    Text(msg)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 8)
            
            // Close Button (Крестик)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.14).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(toast.isError ? Color.red.opacity(0.4) : Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 6)
        )
        .padding(.horizontal, 16)
    }
}
