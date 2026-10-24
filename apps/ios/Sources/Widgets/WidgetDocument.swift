import Foundation

/// Politique réseau d'un widget. Par défaut : aucun accès.
public enum WidgetNetworkPolicy: Hashable, Sendable {
    case none
    /// Hôtes HTTPS explicitement autorisés (schéma + hôte, sans chemin ni joker global).
    case allowedHosts([String])

    var validatedHosts: [String] {
        guard case let .allowedHosts(hosts) = self else { return [] }
        return hosts.compactMap { raw in
            let host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ok = !host.isEmpty && host.count <= 253 &&
                host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" } &&
                !host.hasPrefix(".") && !host.hasPrefix("-") && host.contains(".")
            return ok ? "https://\(host)" : nil
        }
    }
}

/// Construit le document chargé dans la WebView : CSP stricte, viewport, thème clair/sombre.
enum WidgetDocument {
    static func csp(allowsScripts: Bool, network: WidgetNetworkPolicy) -> String {
        let hosts = network.validatedHosts.joined(separator: " ")
        var parts = [
            "default-src 'none'",
            "img-src data: blob: \(hosts)",
            "style-src 'unsafe-inline' \(hosts)",
            "font-src data: \(hosts)",
            "media-src 'none'",
            "frame-src 'none'",
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'none'",
            "connect-src \(hosts.isEmpty ? "'none'" : hosts)",
        ]
        parts.append(allowsScripts ? "script-src 'unsafe-inline' \(hosts)" : "script-src 'none'")
        return parts.joined(separator: "; ")
    }

    static func html(for payload: WidgetPayload, network: WidgetNetworkPolicy, zoomable: Bool) -> String? {
        let body: String
        let scripts: Bool
        switch payload {
        case let .html(source, allowsScripts):
            body = source
            scripts = allowsScripts
        case let .svg(source):
            body = Self.stripSVGActiveContent(source)
            scripts = false
        case .chart:
            return nil
        }
        let viewport = zoomable
            ? "width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=5, user-scalable=yes"
            : "width=device-width, initial-scale=1, maximum-scale=1"
        // La meta CSP vient en premier dans <head> : le contenu de l'assistant ne peut pas la précéder.
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(Self.csp(allowsScripts: scripts, network: network))">
        <meta name="viewport" content="\(viewport)">
        <meta name="color-scheme" content="light dark">
        <style>
        :root{color-scheme:light dark}
        html,body{margin:0;padding:0;background:transparent;color:CanvasText;font:-apple-system-body;
          -webkit-text-size-adjust:100%;word-wrap:break-word}
        a{color:LinkText}
        body{padding:12px}
        svg{max-width:100%;height:auto}
        img{max-width:100%;height:auto}
        </style></head><body>\(body)</body></html>
        """
    }

    /// Défense en profondeur (la CSP bloque déjà les scripts SVG) : retire <script>, on*= et href javascript:.
    static func stripSVGActiveContent(_ svg: String) -> String {
        var out = svg
        let patterns = [
            #"(?is)<script\b.*?</script\s*>"#,
            #"(?is)<foreignObject\b.*?</foreignObject\s*>"#,
            #"(?i)\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            #"(?i)(href|xlink:href)\s*=\s*("\s*javascript:[^"]*"|'\s*javascript:[^']*')"#,
        ]
        for pattern in patterns {
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return out
    }
}
