import QModel
import QDomain
import QNetwork
import QData
import QGrader
import QDesign
import QKeyboard

public enum QFeaturesInfo {
    public static let name = "QFeatures"
    public static let dependencyNames: [String] = [QModelInfo.name, QDomainInfo.name, QNetworkInfo.name, QDataInfo.name, QGraderInfo.name, QDesignInfo.name, QKeyboardInfo.name]
}
