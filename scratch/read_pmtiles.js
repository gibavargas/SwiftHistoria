import fs from "fs";
import { PMTiles } from "pmtiles";

// Simple custom Source for nodejs fs
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
        const source = new NodeFileSource("public/saves/save0/countries.pmtiles");
        const pmtiles = new PMTiles(source);
        const header = await pmtiles.getHeader();
        console.log("Header:", header);
        const metadata = await pmtiles.getMetadata();
        console.log("Metadata:", metadata);
    } catch (err) {
        console.error(err);
    }
}
run();
