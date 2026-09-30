import Cocoa
import SwiftUI

final class AboutViewController: NSViewController {
    static func initWithStoryboard() -> AboutViewController {
        NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "aboutVC") as! AboutViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let hostingView = NSHostingView(rootView: AboutSettingsView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 460),
            view.heightAnchor.constraint(equalToConstant: 370),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

private struct AboutSettingsView: View {
    private var versionText: String {
        let version = Bundle.main.releaseVersionNumber ?? ""
        let build = Bundle.main.buildVersionNumber ?? ""
        return "\("Version".localized) \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hidden Bar").font(.title2).fontWeight(.semibold)
                    Text("Menu bar cleaner".localized).foregroundStyle(.secondary)
                    Text(verbatim: versionText)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 20) {
                Link("Source code".localized, destination: URL(string: "https://github.com/dwarvesf/hidden")!)
                Link("Report an issue".localized, destination: URL(string: "https://github.com/dwarvesf/hidden/issues")!)
            }
            VStack(spacing: 6) {
                Text("MIT © Dwarves Foundation")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .font(.system(size: 13))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
