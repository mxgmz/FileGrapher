// Headless assert-harness for Folder-Canvas Phase 2 "bound auto-grow" (the outlier filter that keeps one
// scattered box from ballooning its folder). Mirrors AppModel.autoGrowChildren (Model.swift): port the
// pure logic, assert, run via `swift Tests/AutoGrowBoundTests.swift`. Standalone — not in the SwiftPM target.
//
// Contract: exclude a child farther than autoGrowOutlierRadius from the SIBLING MEDIAN; keep a tall-but-
// clustered stack (each box near its neighbors); keep a single child; fall back to all if the filter empties.

import Foundation

let autoGrowOutlierRadius: Double = 6000
func median(_ v: [Double]) -> Double {
    let s = v.sorted(); let m = s.count/2
    return s.isEmpty ? 0 : (s.count % 2 == 0 ? (s[m-1]+s[m])/2 : s[m])
}
struct C { var x: Double; var y: Double }
// ported from AppModel.autoGrowChildren
func autoGrowChildren(_ kids: [C]) -> [C] {
    guard kids.count > 1 else { return kids }
    let mx = median(kids.map{$0.x}), my = median(kids.map{$0.y})
    let near = kids.filter { (($0.x-mx)*($0.x-mx)+($0.y-my)*($0.y-my)).squareRoot() <= autoGrowOutlierRadius }
    return near.isEmpty ? kids : near
}

var fails = 0
func check(_ n: String, _ p: Bool){ print((p ? "ok   " : "FAIL ")+n); if !p { fails+=1 } }

// 1. Cluster of 4 near the origin + 1 far outlier → outlier excluded.
let cluster = [C(x:0,y:0),C(x:200,y:100),C(x:-150,y:300),C(x:50,y:-200),C(x:0,y:9000)]
check("far outlier excluded (4 of 5 kept)", autoGrowChildren(cluster).count == 4)
check("the kept ones are the cluster", autoGrowChildren(cluster).allSatisfy { abs($0.y) < 6000 })

// 2. Many children legitimately stacked tall (each ~300px from the next) → ALL kept (none is an outlier
//    vs the median, even though the stack spans 9000px).
let stack = (0..<31).map { C(x:0, y: Double($0)*300) }   // y 0..9000, median ~4500, max dist ~4500 < 6000
check("tall legit stack keeps every child", autoGrowChildren(stack).count == 31)

// 3. Single child → kept (no median games).
check("single child kept", autoGrowChildren([C(x:0,y:50000)]).count == 1)

// 4. Two children far apart (each is the other's outlier vs their midpoint median) → fallback keeps both.
check("degenerate all-far falls back to all", autoGrowChildren([C(x:0,y:0),C(x:0,y:40000)]).count == 2)

// 5. Threshold boundary: a child just under the radius is kept; just past is dropped. Odd count so the
//    median is a single value (y=0): the three at origin + the 5999 stay, the 6001 drops → 4 of 5 kept.
let edge = [C(x:0,y:0),C(x:0,y:0),C(x:0,y:0),C(x:0,y:5999),C(x:0,y:6001)]
check("child <radius kept, child >radius dropped (4 of 5)", autoGrowChildren(edge).count == 4)

print(fails == 0 ? "\nALL PASS" : "\n\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
