import Foundation

public protocol ScanProgressDelegate: AnyObject {
    func didStartInspecting()
    func didStartBuilding(scheme: String)
    func didStartIndexing()
    func didStartAnalyzing()
}
