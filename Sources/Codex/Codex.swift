public enum InputItem: Sendable, Hashable, Codable {
    case text(String)
    case image(url: String)
    case localImage(path: String)
    case skill(name: String, path: String)
    case mention(name: String, path: String)
}
