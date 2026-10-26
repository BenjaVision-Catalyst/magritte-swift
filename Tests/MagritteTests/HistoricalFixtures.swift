import Foundation

// Older GT fixtures projected derived label defaults to raw accessor keys.
// Fresh inference fixtures check actual defaults without this historical projection.
func withoutHistoricalLabelDefaults(_ graph: [String: Any]) -> [String: Any] {
  guard var nodes = graph["descriptions"] as? [[String: Any]] else { return graph }
  var result = graph
  for i in nodes.indices {
    if let accessor = nodes[i]["accessor"] as? [String: Any],
      accessor["readSelector"] as? String == "label",
      var properties = nodes[i]["properties"] as? [String: Any]
    {
      properties.removeValue(forKey: "default")
      nodes[i]["properties"] = properties
    }
  }
  result["descriptions"] = nodes
  return result
}
