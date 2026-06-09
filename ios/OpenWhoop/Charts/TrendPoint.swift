import Foundation

// Shared chart point model used by metric and heart-rate charts.

struct TrendPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let value: Double
}
