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

async function run() {
    try {
        const source = new NodeFileSource("public/saves/save0/regions.pmtiles");
        const pmtiles = new PMTiles(source);
        const tileData = await pmtiles.getZxy(0, 0, 0);
        if (!tileData || !tileData.data) {
            console.log("No tile data found at (0, 0, 0)");
            return;
        }

        const tile = new VectorTile(new Pbf(new Uint8Array(tileData.data)));
        console.log("Layers:", Object.keys(tile.layers));
        const layer = tile.layers.regions;
        console.log("Layer regions features count:", layer.length);

        // Print first 5 features
        for (let i = 0; i < Math.min(5, layer.length); i++) {
            const feat = layer.feature(i);
            console.log(`Feature ${i}:`, feat.properties);
        }
    } catch (err) {
        console.error(err);
    }
}
run();
