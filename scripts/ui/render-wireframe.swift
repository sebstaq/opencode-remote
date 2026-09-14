// Render the wireframe sidebar on macOS with WebKit (real system font) for a fair
// font-for-font diff against the iOS app. Run on the VM:
//   swift render-wireframe.swift <index.html> <out.png>
import AppKit
import WebKit

let args = CommandLine.arguments
let htmlPath = args.count > 1 ? args[1] : "index.html"
let outPath = args.count > 2 ? args[2] : "/tmp/sidebar_wire.png"

let css = """
.page-head{display:none}
.stage{padding:0;gap:0;justify-content:flex-start}
html,body{overflow:hidden;background:#fff}
.device{width:393px;height:852px;border:0;border-radius:0}
.statusbar{height:59px}
.drawer{top:59px;width:330px}
.sliver{top:59px;left:330px}
.sb{height:calc(852px - 59px)}
.chat{height:calc(852px - 59px)}
.empty{height:calc(852px - 59px)}
"""

let js = """
(function(){
  var s=document.createElement('style');
  s.textContent = document.getElementById('__wirecss').textContent;
  document.head.appendChild(s);
  app.nav('sidebar');
})()
"""

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let frame = NSRect(x: 0, y: 0, width: 393, height: 852)
let config = WKWebViewConfiguration()
let webView = WKWebView(frame: frame, configuration: config)

// Inline the CSS in a <script type="text/css"> node so JS can apply it after load.
let escapedCSS = css.replacingOccurrences(of: "</", with: "<\\/")
let injection = WKUserScript(
  source:
    "var t=document.createElement('script');t.type='text/css';t.id='__wirecss';"
    + "t.textContent=\(jsString(escapedCSS));document.documentElement.appendChild(t);",
  injectionTime: .atDocumentEnd,
  forMainFrameOnly: true
)
webView.configuration.userContentController.addUserScript(injection)

let window = NSWindow(
  contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = webView
window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
window.orderFrontRegardless()

final class Delegate: NSObject, WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    webView.evaluateJavaScript(js) { _, error in
      if let error {
        FileHandle.standardError.write("eval error: \(error)\n".data(using: .utf8)!)
        exit(1)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let snapshot = WKSnapshotConfiguration()
        snapshot.snapshotWidth = 1179
        webView.takeSnapshot(with: snapshot) { image, error in
          guard let image,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
          else {
            FileHandle.standardError.write(
              "snapshot failed: \(String(describing: error))\n".data(using: .utf8)!)
            exit(1)
          }
          try? png.write(to: URL(fileURLWithPath: outPath))
          print(outPath)
          exit(0)
        }
      }
    }
  }
}

func jsString(_ value: String) -> String {
  let data = try! JSONSerialization.data(withJSONObject: [value])
  let array = String(data: data, encoding: .utf8)!
  return String(array.dropFirst().dropLast())
}

let delegate = Delegate()
webView.navigationDelegate = delegate
webView.loadFileURL(
  URL(fileURLWithPath: htmlPath),
  allowingReadAccessTo: URL(fileURLWithPath: htmlPath).deletingLastPathComponent()
)
app.run()
