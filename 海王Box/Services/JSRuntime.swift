import Foundation
import JavaScriptCore

/// JS 爬虫运行时（对应安卓 QuickJS + js/lib + js/lx）
/// 用 iOS 原生 JavaScriptCore 加载猫影视 cat.js / 洛雪 lx 脚本，
/// 并把网络、存储、日志等宿主能力通过 JSExport 注入，使第三方采集脚本可执行。
final class JSRuntime: NSObject, ObservableObject {

    static let shared = JSRuntime()

    private var context: JSContext!
    private var bridge: JSBridge!
    @Published var loadedLibs: [String] = []
    @Published var lastError: String? = nil

    override init() {
        super.init()
        setup()
    }

    // MARK: - 初始化
    private func setup() {
        context = JSContext()
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastError = exception?.toString() ?? "未知 JS 异常"
        }
        bridge = JSBridge()
        context.setObject(bridge, forKeyedSubscript: "nativeBridge" as NSCopying)
        // 兼容 cat.js 常见的宿主全局
        context.evaluateScript("""
        var console = { log: function(){ nativeBridge.log(Array.prototype.join.call(arguments,' ')); } };
        var localStorage = {
            getItem: function(k){ return nativeBridge.getStorage(k); },
            setItem: function(k,v){ nativeBridge.setStorage(k,String(v)); },
            removeItem: function(k){ nativeBridge.removeStorage(k); }
        };
        """)
        loadLibScripts()
    }

    /// 加载 Resources/js/lib 下的基础库（顺序有依赖）
    func loadLibScripts() {
        let order = ["utils.js", "gbk.js", "crypto-js.js", "cheerio.min.js", "http.js", "net.js", "cat.js",
                     "lx/polyfill.js", "lx/lx_bridge.js", "lx/user-api-preload.js", "lx/lx_official_shim.js"]
        let base = Bundle.main.resourceURL?.appendingPathComponent("js")
        var loaded: [String] = []
        for rel in order {
            guard let url = base?.appendingPathComponent(rel),
                  let code = try? String(contentsOf: url, encoding: .utf8) else { continue }
            context.evaluateScript(code)
            loaded.append(rel)
        }
        loadedLibs = loaded
    }

    // MARK: - 执行采集脚本
    /// 执行 spider 脚本的某个动作（init / home / category / detail / search / play）
    func execute(script: String, action: String, params: [String: Any]) async -> [String: Any]? {
        // 在脚本后追加导出调用，结果写回全局变量
        let paramJSON = (try? JSONSerialization.data(withJSONObject: params)) .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let wrapper = """
        (function(){
          try {
            var __cfg = (\(paramJSON));
            var __result = null;
            if (typeof spider !== 'undefined' && typeof spider.\(action) === 'function') {
              __result = spider.\(action)(__cfg);
            } else if (typeof \(action) === 'function') {
              __result = \(action)(__cfg);
            }
            nativeBridge.setLastResult(JSON.stringify(__result === undefined ? null : __result));
          } catch(e) { nativeBridge.setLastResult(JSON.stringify({__error: String(e)})); }
        })();
        """
        context.evaluateScript(script)
        context.evaluateScript(wrapper)
        let json = bridge.lastResult
        bridge.lastResult = ""
        guard let data = json?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if obj["__error"] != nil { lastError = obj["__error"] as? String; return nil }
        return obj
    }

    /// 让 JS 侧同步请求（cat.js 的 js: 约定常被封装成同步），这里提供 Promise 风格的异步桥
    func evaluateAsync(_ code: String) async -> String? {
        context.evaluateScript(code)
        return bridge.lastResult
    }
}

// MARK: - 原生桥接对象
@objc protocol JSBridgeExport: JSExport {
    func log(_ message: String)
    func getStorage(_ key: String) -> String?
    func setStorage(_ key: String, _ value: String)
    func removeStorage(_ key: String)
    func setLastResult(_ json: String)
}

@objc final class JSBridge: NSObject, JSBridgeExport {
    var lastResult: String = ""

    func log(_ message: String) { print("[JS] \(message)") }
    func getStorage(_ key: String) -> String? { UserDefaults.standard.string(forKey: "js_\(key)") }
    func setStorage(_ key: String, _ value: String) { UserDefaults.standard.set(value, forKey: "js_\(key)") }
    func removeStorage(_ key: String) { UserDefaults.standard.removeObject(forKey: "js_\(key)") }
    func setLastResult(_ json: String) { lastResult = json }
}
