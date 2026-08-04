import SwiftUI
import YushiKit

/// 进入完整聊天的宿主。
/// 顶栏归 ChatScreen 自己管（返回键、头像、名字、搜索入口都在那一条上），
/// 这里只负责把联系人递进去，以及没匹配到网关联系人时的占位。
struct ChatSheetView: View {
    let spec: PetSpec
    let contact: ContactListItem?
    var onBack: () -> Void

    var body: some View {
        if let contact {
            ChatScreen(item: contact, onBack: onBack)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            SceneTokens.paperPage.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("和\(spec.name)的完整对话")
                    .font(.system(size: 14))
                    .tracking(0.84)
                    .foregroundStyle(SceneTokens.ink500)
                Text("还没匹配到网关联系人 · 去「案头」连上后，这里直通聊天")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SceneTokens.ink400)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(SceneTokens.sage400, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
            .padding(EdgeInsets(top: 24, leading: 16, bottom: 44, trailing: 16))
        }
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(SceneTokens.ink600)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
    }
}

/// 速览卡与聊天页共用的小头像：取 idle 立绘的头部取景。
/// 框里的 pet 是静止的——它是「照片」，不是活物。
struct PetAvatarView: View {
    let spec: PetSpec
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneAsset.image(spec.art(.idle))
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.7)
                .offset(x: -size * 0.35, y: -size * 0.06)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .background(SceneTokens.cream300)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(SceneTokens.cream500, lineWidth: 1.5))
    }
}
