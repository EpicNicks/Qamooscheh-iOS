import QModel
import QNetwork

public enum QDataInfo {
    public static let name = "QData"
    public static let dependencyNames: [String] = [QModelInfo.name, QNetworkInfo.name]
}
