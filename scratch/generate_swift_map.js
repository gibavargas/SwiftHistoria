import fs from "fs";
import { PMTiles } from "pmtiles";
import { VectorTile } from "@mapbox/vector-tile";
import Pbf from "pbf";

class NodeFileSource {
    constructor(path) {
        this.fd = fs.openSync(path, "r");
    }
    getKey() {
        return "node-file";
    }
    async getBytes(offset, length) {
        const buffer = Buffer.alloc(length);
        const { bytesRead } = fs.readSync(this.fd, buffer, 0, length, offset);
        return { data: buffer.buffer.slice(0, bytesRead) };
    }
}

// Coordinate conversions
const tileToLngLat = (px, py, extent = 4096) => {
    const lng = (px / extent) * 360 - 180;
    const latRad = Math.atan(Math.sinh(Math.PI * (1 - (2 * py) / extent)));
    const lat = latRad * (180 / Math.PI);
    return [lng, lat];
};

function projectLongitude(lon) {
    const controlPoints = [
        [-180.0, 0.0],
        [-100.0, 190.0],
        [-50.0, 290.0],
        [0.0, 420.0],
        [10.0, 460.0],
        [30.0, 540.0],
        [80.0, 670.0],
        [105.0, 760.0],
        [135.0, 870.0],
        [180.0, 1000.0]
    ];
    if (lon <= controlPoints[0][0]) return controlPoints[0][1];
    if (lon >= controlPoints[controlPoints.length - 1][0]) return controlPoints[controlPoints.length - 1][1];
    for (let i = 0; i < controlPoints.length - 1; i++) {
        const p1 = controlPoints[i];
        const p2 = controlPoints[i+1];
        if (lon >= p1[0] && lon <= p2[0]) {
            const t = (lon - p1[0]) / (p2[0] - p1[0]);
            return p1[1] + t * (p2[1] - p1[1]);
        }
    }
    return 500.0;
}

function projectLatitude(lat) {
    const controlPoints = [
        [80.0, 40.0],
        [60.0, 90.0],
        [40.0, 160.0],
        [20.0, 230.0],
        [0.0, 300.0],
        [-15.0, 380.0],
        [-30.0, 490.0],
        [-45.0, 540.0],
        [-60.0, 570.0],
        [-90.0, 590.0]
    ];
    if (lat >= controlPoints[0][0]) return controlPoints[0][1];
    if (lat <= controlPoints[controlPoints.length - 1][0]) return controlPoints[controlPoints.length - 1][1];
    for (let i = 0; i < controlPoints.length - 1; i++) {
        const p1 = controlPoints[i];
        const p2 = controlPoints[i+1];
        if (lat <= p1[0] && lat >= p2[0]) {
            const t = (lat - p1[0]) / (p2[0] - p1[0]);
            return p1[1] + t * (p2[1] - p1[1]);
        }
    }
    return 300.0;
}

function getTerrainForRegion(id, countryCode) {
    if (countryCode === "WATER") {
        if (["GIBRALTAR", "PANAMA_CANAL"].includes(id)) {
            return "strait";
        }
        if (["MEDITERRANEAN", "SOUTH_CHINA_SEA"].includes(id)) {
            return "sea";
        }
        return "ocean";
    }

    const mountainCodes = ["CHE", "NPL", "BTN", "AFG", "AND", "KGZ", "TJK", "BOL", "PER", "CHL", "GEO", "ARM"];
    if (mountainCodes.includes(countryCode) || id === "USA_WEST" || id === "CHN_WEST" || id === "RUS_EAST") {
        return "mountain";
    }

    const forestCodes = ["COD", "COG", "GAB", "GNQ", "FIN", "SWE", "SUR", "GUY"];
    if (forestCodes.includes(countryCode) || id === "BRA_NORTH" || id === "CAN") {
        return "forest";
    }

    const cerradoCodes = ["AGO", "ZMB", "TZA", "KEN", "ZWE", "BWA", "ZAF"];
    if (cerradoCodes.includes(countryCode) || id === "BRA_SOUTH") {
        return "cerrado";
    }

    const swampCodes = ["SSD", "BGD", "BLR", "VEN", "IRQ"];
    if (swampCodes.includes(countryCode)) {
        return "swamp";
    }

    const cityCodes = ["SGP", "MCO", "VAT", "HKG", "MAC", "MLT", "BHR", "MDV"];
    if (cityCodes.includes(countryCode)) {
        return "city";
    }

    return "plains";
}

// Ramer-Douglas-Peucker simplification
function getSqSegDist(p, p1, p2) {
    let x = p1[0];
    let y = p1[1];
    let dx = p2[0] - x;
    let dy = p2[1] - y;

    if (dx !== 0 || dy !== 0) {
        let t = ((p[0] - x) * dx + (p[1] - y) * dy) / (dx * dx + dy * dy);
        if (t > 1) {
            x = p2[0];
            y = p2[1];
        } else if (t > 0) {
            x += dx * t;
            y += dy * t;
        }
    }

    dx = p[0] - x;
    dy = p[1] - y;
    return dx * dx + dy * dy;
}

function simplifyDPStep(points, first, last, sqTolerance, simplified) {
    let maxSqDist = sqTolerance;
    let index;

    for (let i = first + 1; i < last; i++) {
        const sqDist = getSqSegDist(points[i], points[first], points[last]);
        if (sqDist > maxSqDist) {
            index = i;
            maxSqDist = sqDist;
        }
    }

    if (maxSqDist > sqTolerance) {
        if (index - first > 1) simplifyDPStep(points, first, index, sqTolerance, simplified);
        simplified.push(points[index]);
        if (last - index > 1) simplifyDPStep(points, index, last, sqTolerance, simplified);
    }
}

function simplifyDouglasPeucker(points, tolerance) {
    if (points.length <= 2) return points;
    const sqTolerance = tolerance * tolerance;
    const simplified = [points[0]];
    simplifyDPStep(points, 0, points.length - 1, sqTolerance, simplified);
    simplified.push(points[points.length - 1]);
    return simplified;
}

// Sutherland-Hodgman Polygon Clipping
function clipPolygon(poly, nx, ny, px, py) {
    let output = [];
    if (!poly || poly.length === 0) return [];
    let s = poly[poly.length - 1];
    for (let i = 0; i < poly.length; i++) {
        let p = poly[i];
        let sInside = (s[0] - px) * nx + (s[1] - py) * ny >= 0;
        let pInside = (p[0] - px) * nx + (p[1] - py) * ny >= 0;
        if (pInside) {
            if (!sInside) {
                let denom = (p[0] - s[0]) * nx + (p[1] - s[1]) * ny;
                let t = denom !== 0 ? ((px - s[0]) * nx + (py - s[1]) * ny) / denom : 0;
                output.push([s[0] + t * (p[0] - s[0]), s[1] + t * (p[1] - s[1])]);
            }
            output.push(p);
        } else if (sInside) {
            let denom = (p[0] - s[0]) * nx + (p[1] - s[1]) * ny;
            let t = denom !== 0 ? ((px - s[0]) * nx + (py - s[1]) * ny) / denom : 0;
            output.push([s[0] + t * (p[0] - s[0]), s[1] + t * (p[1] - s[1])]);
        }
        s = p;
    }
    return output;
}

// Calculate centroid
function getCentroid(points) {
    let x = 0;
    let y = 0;
    let area = 0;

    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
        const p1 = points[i];
        const p2 = points[j];
        const factor = p1[0] * p2[1] - p2[0] * p1[1];
        area += factor;
        x += (p1[0] + p2[0]) * factor;
        y += (p1[1] + p2[1]) * factor;
    }

    const scale = (area * 3) || 1;
    return [x / scale, y / scale];
}

function getArea(points) {
    let area = 0;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
        area += (points[j][0] + points[i][0]) * (points[j][1] - points[i][1]);
    }
    return Math.abs(area / 2);
}

// Parse PlayerCountry.swift to get all country codes
const playerCountryContent = fs.readFileSync("Apple/PaxHistoriaApple/PlayerCountry.swift", "utf8");
const countryCodes = [...playerCountryContent.matchAll(/alpha3:\s*"([A-Z]{3})"/g)].map(m => m[1]);

// Filter out unavailable countries (SSD)
const selectables = new Set(countryCodes.filter(code => code !== "SSD"));
console.log(`Selectable countries count: ${selectables.size}`);

// Parse NativeCountryCoordinates.swift to get centroids
const coordinatesContent = fs.readFileSync("Apple/PaxHistoriaApple/NativeCountryCoordinates.swift", "utf8");
const centroidsMap = {};
for (const match of coordinatesContent.matchAll(/"([A-Z0-9]{3})":\s*\(([^,]+),\s*([^)]+)\)/g)) {
    centroidsMap[match[1]] = [parseFloat(match[2]), parseFloat(match[3])];
}

async function run() {
    try {
        const source = new NodeFileSource("public/saves/save0/countries.pmtiles");
        const pmtiles = new PMTiles(source);
        const tileData = await pmtiles.getZxy(0, 0, 0);
        if (!tileData || !tileData.data) {
            throw new Error("No tile data found at (0, 0, 0)");
        }

        const tile = new VectorTile(new Pbf(new Uint8Array(tileData.data)));
        const layer = tile.layers.countries;

        let regions = [];
        const seenCodes = new Set();

        for (let i = 0; i < layer.length; i++) {
            const feat = layer.feature(i);
            const countryCode = feat.properties.GID_0;
            if (!selectables.has(countryCode)) {
                continue;
            }

            seenCodes.add(countryCode);
            const name = feat.properties.COUNTRY;
            const geom = feat.loadGeometry();
            const rawPolygons = geom.map(ring => ring.map(pt => tileToLngLat(pt.x, pt.y, layer.extent)));

            if (countryCode === "USA") {
                let westPolys = [];
                let eastPolys = [];
                for (const poly of rawPolygons) {
                    const west = clipPolygon(poly, -1, 0, -96.0, 0);
                    const east = clipPolygon(poly, 1, 0, -96.0, 0);
                    if (west.length >= 3) westPolys.push(west);
                    if (east.length >= 3) eastPolys.push(east);
                }
                regions.push({ id: "USA_WEST", countryCode, name: "USA West", rawPolys: westPolys });
                regions.push({ id: "USA_EAST", countryCode, name: "USA East", rawPolys: eastPolys });
            } else if (countryCode === "BRA") {
                let northPolys = [];
                let southPolys = [];
                for (const poly of rawPolygons) {
                    const north = clipPolygon(poly, 0, 1, 0, -12.0);
                    const south = clipPolygon(poly, 0, -1, 0, -12.0);
                    if (north.length >= 3) northPolys.push(north);
                    if (south.length >= 3) southPolys.push(south);
                }
                regions.push({ id: "BRA_NORTH", countryCode, name: "Brazil North", rawPolys: northPolys });
                regions.push({ id: "BRA_SOUTH", countryCode, name: "Brazil South", rawPolys: southPolys });
            } else if (countryCode === "CHN") {
                let northPolys = [];
                let southPolys = [];
                for (const poly of rawPolygons) {
                    const north = clipPolygon(poly, 0, 1, 0, 32.0);
                    const south = clipPolygon(poly, 0, -1, 0, 32.0);
                    if (north.length >= 3) northPolys.push(north);
                    if (south.length >= 3) southPolys.push(south);
                }
                regions.push({ id: "CHN_NORTH", countryCode, name: "China North", rawPolys: northPolys });
                regions.push({ id: "CHN_SOUTH", countryCode, name: "China South", rawPolys: southPolys });
            } else if (countryCode === "RUS") {
                let westPolys = [];
                let eastPolys = [];
                for (const poly of rawPolygons) {
                    const west = clipPolygon(poly, -1, 0, 60.0, 0);
                    const east = clipPolygon(poly, 1, 0, 60.0, 0);
                    if (west.length >= 3) westPolys.push(west);
                    if (east.length >= 3) eastPolys.push(east);
                }
                regions.push({ id: "RUS_WEST", countryCode, name: "Eurasia West", rawPolys: westPolys });
                regions.push({ id: "RUS_EAST", countryCode, name: "Eurasia East", rawPolys: eastPolys });
            } else {
                regions.push({ id: countryCode, countryCode, name, rawPolys: rawPolygons });
            }
        }

        // Custom Water Regions
        const waterSpecs = [
            { id: "ATLANTIC", name: "Atlantic Ocean", centerLon: -40.0, centerLat: 15.0, widthLon: 15.0, widthLat: 15.0 },
            { id: "PACIFIC_WEST", name: "Pacific Ocean West", centerLon: -160.0, centerLat: 0.0, widthLon: 15.0, widthLat: 15.0 },
            { id: "PACIFIC_EAST", name: "Pacific Ocean East", centerLon: 160.0, centerLat: 0.0, widthLon: 15.0, widthLat: 15.0 },
            { id: "INDIAN", name: "Indian Ocean", centerLon: 75.0, centerLat: -20.0, widthLon: 15.0, widthLat: 15.0 },
            { id: "MEDITERRANEAN", name: "Mediterranean Sea", centerLon: 18.0, centerLat: 35.0, widthLon: 6.0, widthLat: 3.0 },
            { id: "SOUTH_CHINA_SEA", name: "South China Sea", centerLon: 115.0, centerLat: 12.0, widthLon: 6.0, widthLat: 6.0 },
            { id: "GIBRALTAR", name: "Strait of Gibraltar", centerLon: -5.6, centerLat: 36.0, widthLon: 1.5, widthLat: 1.0 },
            { id: "PANAMA_CANAL", name: "Panama Canal", centerLon: -79.7, centerLat: 9.0, widthLon: 1.5, widthLat: 1.0 }
        ];

        for (const spec of waterSpecs) {
            const wl = spec.widthLon;
            const wt = spec.widthLat;
            const poly = [
                [spec.centerLon - wl, spec.centerLat - wt],
                [spec.centerLon + wl, spec.centerLat - wt],
                [spec.centerLon + wl, spec.centerLat + wt],
                [spec.centerLon - wl, spec.centerLat + wt],
                [spec.centerLon - wl, spec.centerLat - wt]
            ];
            regions.push({
                id: spec.id,
                countryCode: "WATER",
                name: spec.name,
                rawPolys: [poly]
            });
        }

        // Find missing selectable countries and generate fallback square polygons
        const missingCodes = [...selectables].filter(code => !seenCodes.has(code));
        console.log(`Missing countries from PMTiles: ${missingCodes.length} (${missingCodes.join(", ")})`);

        for (const code of missingCodes) {
            const centroidCoord = centroidsMap[code] || [0, 0];
            const lat = centroidCoord[0];
            const lon = centroidCoord[1];

            // Build a small 4-point square polygon (approx. 0.5 degrees radius)
            const r = 0.5;
            const poly = [
                [lon - r, lat - r],
                [lon + r, lat - r],
                [lon + r, lat + r],
                [lon - r, lat + r],
                [lon - r, lat - r]
            ];

            // Look up display name or use code
            const nameMatch = playerCountryContent.match(new RegExp(`alpha3:\\s*"${code}"`));
            let name = code;

            regions.push({
                id: code,
                countryCode: code,
                name: name,
                rawPolys: [poly]
            });
        }

        console.log(`Processing total ${regions.length} regions.`);

        let formattedRegions = [];
        let allLandmassPolygons = [];

        for (const reg of regions) {
            let projectedPolys = [];
            for (const poly of reg.rawPolys) {
                const proj = poly.map(([lon, lat]) => [
                    projectLongitude(lon),
                    projectLatitude(lat)
                ]);
                projectedPolys.push(proj);
            }

            // Simplify (pixel tolerance = 1.0)
            let simplifiedPolys = projectedPolys.map(poly => simplifyDouglasPeucker(poly, 1.0))
                .filter(poly => poly.length >= 3);

            if (simplifiedPolys.length === 0) {
                simplifiedPolys = projectedPolys.filter(poly => poly.length >= 3);
            }

            let maxArea = -1;
            let mainPoly = null;
            for (const poly of simplifiedPolys) {
                const a = getArea(poly);
                if (a > maxArea) {
                    maxArea = a;
                    mainPoly = poly;
                }
            }

            if (!mainPoly) {
                console.error(`Error: No valid polygon for region ${reg.id}`);
                continue;
            }

            const centroid = getCentroid(mainPoly);

            formattedRegions.push({
                id: reg.id,
                countryCode: reg.countryCode,
                name: reg.name,
                points: mainPoly.map(([x, y]) => [Math.round(x * 100) / 100, Math.round(y * 100) / 100]),
                center: [Math.round(centroid[0] * 100) / 100, Math.round(centroid[1] * 100) / 100],
                terrain: getTerrainForRegion(reg.id, reg.countryCode)
            });

            allLandmassPolygons.push(...simplifiedPolys);
        }

        // Landmasses: sort and take the top 50 largest
        let sortedPolys = allLandmassPolygons.map(poly => ({ poly, area: getArea(poly) }))
            .sort((a, b) => b.area - a.area);

        let topLandmasses = sortedPolys.slice(0, 45).map((item, idx) => ({
            id: `lm_${idx}`,
            points: item.poly.map(([x, y]) => [Math.round(x * 100) / 100, Math.round(y * 100) / 100])
        }));

        console.log(`Generated ${formattedRegions.length} regions and ${topLandmasses.length} landmasses.`);

        // Generate the Swift code
        let swiftCode = `import SwiftUI

struct MapRegion: Identifiable, Hashable {
    let id: String         // e.g. "USA_WEST", "CHN_NORTH"
    let countryCode: String // e.g. "USA", "CHN"
    let name: String
    let points: [CGPoint]
    let center: CGPoint
    let terrain: NativeTerrainType
}

struct LandmassOutline: Identifiable, Hashable {
    let id: String
    let points: [CGPoint]
}

enum GeopoliticalMapData {
    static let landmasses: [LandmassOutline] = [
`;

        for (const lm of topLandmasses) {
            const ptsStr = lm.points.map(([x, y]) => `CGPoint(x: ${x}, y: ${y})`).join(", ");
            swiftCode += `        LandmassOutline(id: "${lm.id}", points: [${ptsStr}]),\n`;
        }

        swiftCode += `    ]

    static let regions: [MapRegion] = [
`;

        for (const reg of formattedRegions) {
            const ptsStr = reg.points.map(([x, y]) => `CGPoint(x: ${x}, y: ${y})`).join(", ");
            swiftCode += `        MapRegion(id: "${reg.id}", countryCode: "${reg.countryCode}", name: "${reg.name.replace(/"/g, '\\"')}", points: [${ptsStr}], center: CGPoint(x: ${reg.center[0]}, y: ${reg.center[1]}), terrain: .${reg.terrain}),\n`;
        }

        swiftCode += `    ]
}
`;

        fs.writeFileSync("Apple/PaxHistoriaApple/GeopoliticalMapData.swift", swiftCode);
        console.log("Successfully generated GeopoliticalMapData.swift!");

    } catch (err) {
        console.error(err);
    }
}
run();
