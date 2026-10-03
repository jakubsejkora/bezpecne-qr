import BQCore
import Foundation

/// Network.framework also declares an `IPAddress` protocol; in this module the name always means
/// BQCore's parsed address with its public/private classification.
typealias IPAddress = BQCore.IPAddress
