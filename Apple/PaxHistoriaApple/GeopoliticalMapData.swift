import SwiftUI

struct MapRegion: Identifiable, Hashable {
    let id: String         // e.g. "USA_WEST", "CHN_NORTH"
    let countryCode: String // e.g. "USA", "CHN"
    let name: String
    let points: [CGPoint]
    let center: CGPoint
}

struct LandmassOutline: Identifiable, Hashable {
    let id: String
    let points: [CGPoint]
}

enum GeopoliticalMapData {
    private static let rawLandmasses: [LandmassOutline] = [
        // North America
        LandmassOutline(id: "na", points: [
            CGPoint(x: 30, y: 50), CGPoint(x: 60, y: 30), CGPoint(x: 100, y: 30), CGPoint(x: 150, y: 25),
            CGPoint(x: 200, y: 30), CGPoint(x: 250, y: 35), CGPoint(x: 300, y: 30), CGPoint(x: 340, y: 40),
            CGPoint(x: 360, y: 60), CGPoint(x: 380, y: 90), CGPoint(x: 350, y: 110), CGPoint(x: 330, y: 130),
            CGPoint(x: 300, y: 160), CGPoint(x: 285, y: 200), CGPoint(x: 275, y: 230), CGPoint(x: 265, y: 260),
            CGPoint(x: 250, y: 265), CGPoint(x: 245, y: 245), CGPoint(x: 235, y: 235), CGPoint(x: 215, y: 240),
            CGPoint(x: 200, y: 255), CGPoint(x: 175, y: 265), CGPoint(x: 155, y: 260), CGPoint(x: 140, y: 250),
            CGPoint(x: 120, y: 245), CGPoint(x: 100, y: 210), CGPoint(x: 95, y: 170), CGPoint(x: 105, y: 135),
            CGPoint(x: 90, y: 115), CGPoint(x: 60, y: 90), CGPoint(x: 45, y: 70)
        ]),
        // South America
        LandmassOutline(id: "sa", points: [
            CGPoint(x: 175, y: 270), CGPoint(x: 200, y: 285), CGPoint(x: 235, y: 305), CGPoint(x: 270, y: 305),
            CGPoint(x: 310, y: 310), CGPoint(x: 340, y: 320), CGPoint(x: 355, y: 345), CGPoint(x: 375, y: 380),
            CGPoint(x: 370, y: 420), CGPoint(x: 350, y: 450), CGPoint(x: 315, y: 495), CGPoint(x: 285, y: 535),
            CGPoint(x: 265, y: 565), CGPoint(x: 255, y: 570), CGPoint(x: 250, y: 550), CGPoint(x: 245, y: 510),
            CGPoint(x: 240, y: 470), CGPoint(x: 220, y: 430), CGPoint(x: 205, y: 385), CGPoint(x: 195, y: 345),
            CGPoint(x: 180, y: 315)
        ]),
        // Eurasia
        LandmassOutline(id: "eurasia", points: [
            CGPoint(x: 380, y: 50), CGPoint(x: 430, y: 40), CGPoint(x: 460, y: 35), CGPoint(x: 490, y: 40),
            CGPoint(x: 520, y: 45), CGPoint(x: 560, y: 40), CGPoint(x: 600, y: 35), CGPoint(x: 650, y: 30),
            CGPoint(x: 700, y: 35), CGPoint(x: 760, y: 30), CGPoint(x: 820, y: 25), CGPoint(x: 880, y: 35),
            CGPoint(x: 930, y: 45), CGPoint(x: 960, y: 65), CGPoint(x: 940, y: 95), CGPoint(x: 920, y: 125),
            CGPoint(x: 895, y: 165), CGPoint(x: 875, y: 215), CGPoint(x: 855, y: 245), CGPoint(x: 835, y: 285),
            CGPoint(x: 825, y: 325), CGPoint(x: 810, y: 355), CGPoint(x: 790, y: 370), CGPoint(x: 770, y: 385),
            CGPoint(x: 750, y: 380), CGPoint(x: 730, y: 355), CGPoint(x: 710, y: 335), CGPoint(x: 690, y: 345),
            CGPoint(x: 675, y: 360), CGPoint(x: 660, y: 375), CGPoint(x: 645, y: 350), CGPoint(x: 630, y: 330),
            CGPoint(x: 610, y: 315), CGPoint(x: 590, y: 305), CGPoint(x: 570, y: 290), CGPoint(x: 550, y: 275),
            CGPoint(x: 535, y: 250), CGPoint(x: 520, y: 240), CGPoint(x: 485, y: 245), CGPoint(x: 465, y: 260),
            CGPoint(x: 440, y: 255), CGPoint(x: 420, y: 240), CGPoint(x: 400, y: 220), CGPoint(x: 385, y: 195),
            CGPoint(x: 395, y: 165), CGPoint(x: 420, y: 145), CGPoint(x: 440, y: 130), CGPoint(x: 435, y: 110),
            CGPoint(x: 415, y: 95), CGPoint(x: 395, y: 80)
        ]),
        // Africa
        LandmassOutline(id: "africa", points: [
            CGPoint(x: 405, y: 230), CGPoint(x: 445, y: 225), CGPoint(x: 485, y: 220), CGPoint(x: 525, y: 225),
            CGPoint(x: 555, y: 235), CGPoint(x: 575, y: 250), CGPoint(x: 590, y: 275), CGPoint(x: 580, y: 305),
            CGPoint(x: 595, y: 335), CGPoint(x: 615, y: 355), CGPoint(x: 605, y: 380), CGPoint(x: 590, y: 410),
            CGPoint(x: 575, y: 445), CGPoint(x: 560, y: 480), CGPoint(x: 540, y: 510), CGPoint(x: 520, y: 535),
            CGPoint(x: 505, y: 540), CGPoint(x: 495, y: 525), CGPoint(x: 490, y: 495), CGPoint(x: 485, y: 460),
            CGPoint(x: 480, y: 425), CGPoint(x: 475, y: 395), CGPoint(x: 450, y: 380), CGPoint(x: 430, y: 370),
            CGPoint(x: 415, y: 355), CGPoint(x: 400, y: 335), CGPoint(x: 395, y: 305), CGPoint(x: 395, y: 275),
            CGPoint(x: 400, y: 250)
        ]),
        // Australia
        LandmassOutline(id: "australia", points: [
            CGPoint(x: 790, y: 440), CGPoint(x: 820, y: 430), CGPoint(x: 850, y: 420), CGPoint(x: 870, y: 435),
            CGPoint(x: 895, y: 445), CGPoint(x: 925, y: 460), CGPoint(x: 940, y: 485), CGPoint(x: 935, y: 515),
            CGPoint(x: 915, y: 535), CGPoint(x: 885, y: 540), CGPoint(x: 850, y: 535), CGPoint(x: 820, y: 525),
            CGPoint(x: 795, y: 510), CGPoint(x: 785, y: 480), CGPoint(x: 780, y: 455)
        ]),
        // Antarctica
        LandmassOutline(id: "antarctica", points: [
            CGPoint(x: 50, y: 570), CGPoint(x: 200, y: 565), CGPoint(x: 350, y: 570), CGPoint(x: 500, y: 565),
            CGPoint(x: 650, y: 570), CGPoint(x: 800, y: 565), CGPoint(x: 950, y: 570), CGPoint(x: 950, y: 595),
            CGPoint(x: 50, y: 595)
        ])
    ]

    static let landmasses: [LandmassOutline] = {
        rawLandmasses.map { lm in
            // Apply 2 iterations of Chaikin subdivision/smoothing to render organic, premium coastlines
            LandmassOutline(id: lm.id, points: smoothPolygon(lm.points, iterations: 2))
        }
    }()

    private static func smoothPolygon(_ points: [CGPoint], iterations: Int) -> [CGPoint] {
        var current = points
        for _ in 0..<iterations {
            if current.count < 3 { break }
            var next = [CGPoint]()
            for i in 0..<current.count {
                let p1 = current[i]
                let p2 = current[(i + 1) % current.count]
                let q = CGPoint(x: p1.x * 0.75 + p2.x * 0.25, y: p1.y * 0.75 + p2.y * 0.25)
                let r = CGPoint(x: p1.x * 0.25 + p2.x * 0.75, y: p1.y * 0.25 + p2.y * 0.75)
                next.append(q)
                next.append(r)
            }
            current = next
        }
        return current
    }

    private static func projectLatitude(_ lat: Double) -> CGFloat {
        // Control point spline/lerp to align latitudes perfectly to map space and Southern Hemisphere expansions
        let controlPoints: [(lat: Double, y: Double)] = [
            (80.0, 40.0),
            (60.0, 90.0),
            (40.0, 160.0),
            (20.0, 230.0),
            (0.0, 300.0),
            (-15.0, 380.0),
            (-30.0, 490.0),
            (-45.0, 540.0),
            (-60.0, 570.0),
            (-90.0, 590.0)
        ]
        if lat >= controlPoints.first!.lat { return CGFloat(controlPoints.first!.y) }
        if lat <= controlPoints.last!.lat { return CGFloat(controlPoints.last!.y) }
        for i in 0..<(controlPoints.count - 1) {
            let p1 = controlPoints[i]
            let p2 = controlPoints[i+1]
            if lat <= p1.lat && lat >= p2.lat {
                let t = (lat - p1.lat) / (p2.lat - p1.lat)
                return CGFloat(p1.y + t * (p2.y - p1.y))
            }
        }
        return 300.0
    }

    private static func projectLongitude(_ lon: Double) -> CGFloat {
        // Control point map to align longitudes to map centers of continents
        let controlPoints: [(lon: Double, x: Double)] = [
            (-180.0, 0.0),
            (-100.0, 190.0),
            (-50.0, 290.0),
            (0.0, 420.0),
            (10.0, 460.0),
            (30.0, 540.0),
            (80.0, 670.0),
            (105.0, 760.0),
            (135.0, 870.0),
            (180.0, 1000.0)
        ]
        if lon <= controlPoints.first!.lon { return CGFloat(controlPoints.first!.x) }
        if lon >= controlPoints.last!.lon { return CGFloat(controlPoints.last!.x) }
        for i in 0..<(controlPoints.count - 1) {
            let p1 = controlPoints[i]
            let p2 = controlPoints[i+1]
            if lon >= p1.lon && lon <= p2.lon {
                let t = (lon - p1.lon) / (p2.lon - p1.lon)
                return CGFloat(p1.x + t * (p2.x - p1.x))
            }
        }
        return 500.0
    }

    private static func project(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(x: projectLongitude(longitude), y: projectLatitude(latitude))
    }

    private static func polygonContains(poly: [CGPoint], point: CGPoint) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            if ((poly[i].y > point.y) != (poly[j].y > point.y)) &&
                (point.x < (poly[j].x - poly[i].x) * (point.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x) {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    private static func findLandmass(for centroid: CGPoint, landmasses: [LandmassOutline]) -> String {
        for lm in landmasses {
            if polygonContains(poly: lm.points, point: centroid) {
                return lm.id
            }
        }
        var closestID = landmasses.first?.id ?? ""
        var minDistance = CGFloat.infinity
        for lm in landmasses {
            for pt in lm.points {
                let dist = pow(pt.x - centroid.x, 2) + pow(pt.y - centroid.y, 2)
                if dist < minDistance {
                    minDistance = dist
                    closestID = lm.id
                }
            }
        }
        return closestID
    }

    private static func lineIntersection(s1: CGPoint, s2: CGPoint, p: CGPoint, n: CGPoint) -> CGPoint {
        let d1 = (p.x - s1.x) * n.x + (p.y - s1.y) * n.y
        let d2 = (s2.x - s1.x) * n.x + (s2.y - s1.y) * n.y
        if abs(d2) < 1e-7 { return s1 }
        let t = d1 / d2
        return CGPoint(x: s1.x + t * (s2.x - s1.x), y: s1.y + t * (s2.y - s1.y))
    }

    private static func clipPolygon(_ poly: [CGPoint], point: CGPoint, normal: CGPoint) -> [CGPoint] {
        var output = [CGPoint]()
        if poly.isEmpty { return [] }
        var s = poly.last!
        for p in poly {
            let sInside = (s.x - point.x) * normal.x + (s.y - point.y) * normal.y >= 0
            let pInside = (p.x - point.x) * normal.x + (p.y - point.y) * normal.y >= 0
            if pInside {
                if !sInside {
                    let intersection = lineIntersection(s1: s, s2: p, p: point, n: normal)
                    output.append(intersection)
                }
                output.append(p)
            } else if sInside {
                let intersection = lineIntersection(s1: s, s2: p, p: point, n: normal)
                output.append(intersection)
            }
            s = p
        }
        return output
    }

    struct CentroidInfo {
        let id: String
        let countryCode: String
        let name: String
        let point: CGPoint
    }

    static let regions: [MapRegion] = {
        var centroids = [CentroidInfo]()

        // Add specific multi-region polities to match game rules and E2E assertions
        centroids.append(CentroidInfo(id: "USA_WEST", countryCode: "USA", name: "USA West", point: CGPoint(x: 145, y: 185)))
        centroids.append(CentroidInfo(id: "USA_EAST", countryCode: "USA", name: "USA East", point: CGPoint(x: 235, y: 185)))
        centroids.append(CentroidInfo(id: "BRA_NORTH", countryCode: "BRA", name: "Brazil North", point: CGPoint(x: 290, y: 355)))
        centroids.append(CentroidInfo(id: "BRA_SOUTH", countryCode: "BRA", name: "Brazil South", point: CGPoint(x: 290, y: 460)))
        centroids.append(CentroidInfo(id: "CHN_NORTH", countryCode: "CHN", name: "China North", point: CGPoint(x: 765, y: 245)))
        centroids.append(CentroidInfo(id: "CHN_SOUTH", countryCode: "CHN", name: "China South", point: CGPoint(x: 760, y: 305)))
        centroids.append(CentroidInfo(id: "RUS_WEST", countryCode: "RUS", name: "Eurasia West", point: CGPoint(x: 610, y: 150)))
        centroids.append(CentroidInfo(id: "RUS_EAST", countryCode: "RUS", name: "Eurasia East", point: CGPoint(x: 810, y: 140)))

        let excludedCodes = Set(["USA", "BRA", "CHN", "RUS"])
        for country in CountryCatalog.all {
            if excludedCodes.contains(country.code) { continue }
            let rawCoord = CountryCoordinate.center(for: country.code)
            let projectedPt = project(latitude: rawCoord.latitude, longitude: rawCoord.longitude)
            centroids.append(CentroidInfo(id: country.code, countryCode: country.code, name: country.name, point: projectedPt))
        }

        // Group centroids by closest landmass
        var landmassGroups = [String: [CentroidInfo]]()
        for c in centroids {
            let lmId = findLandmass(for: c.point, landmasses: landmasses)
            landmassGroups[lmId, default: []].append(c)
        }

        var generatedRegions = [MapRegion]()

        // Run Voronoi partitioning per landmass
        for lm in landmasses {
            guard let group = landmassGroups[lm.id], !group.isEmpty else { continue }
            for c in group {
                var cell = lm.points
                // Sort all other centroids in this group by distance
                let neighbors = group.filter { $0.id != c.id }.sorted { c1, c2 in
                    let d1 = pow(c1.point.x - c.point.x, 2) + pow(c1.point.y - c.point.y, 2)
                    let d2 = pow(c2.point.x - c.point.x, 2) + pow(c2.point.y - c.point.y, 2)
                    return d1 < d2
                }

                // Clip cell by the closest neighbors to maintain clean partitioning
                let maxClippedNeighbors = min(18, neighbors.count)
                for i in 0..<maxClippedNeighbors {
                    let n = neighbors[i]
                    let midpoint = CGPoint(x: (c.point.x + n.point.x) * 0.5, y: (c.point.y + n.point.y) * 0.5)
                    // Normal pointing towards the current centroid 'c'
                    let dx = c.point.x - n.point.x
                    let dy = c.point.y - n.point.y
                    let length = sqrt(dx*dx + dy*dy)
                    let normal = length > 0 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: 1, y: 0)
                    cell = clipPolygon(cell, point: midpoint, normal: normal)
                }

                // Fallback to a small bounding box if the cell gets completely clipped or empty
                if cell.count < 3 {
                    cell = [
                        CGPoint(x: c.point.x - 6, y: c.point.y - 6),
                        CGPoint(x: c.point.x + 6, y: c.point.y - 6),
                        CGPoint(x: c.point.x + 6, y: c.point.y + 6),
                        CGPoint(x: c.point.x - 6, y: c.point.y + 6)
                    ]
                }

                generatedRegions.append(MapRegion(
                    id: c.id,
                    countryCode: c.countryCode,
                    name: c.name,
                    points: cell,
                    center: c.point
                ))
            }
        }

        return generatedRegions
    }()
}
