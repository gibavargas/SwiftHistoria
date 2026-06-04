import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const ROOT_DIR = path.resolve(import.meta.dirname, "..");
const PMTILES_MAGIC = Buffer.from("PMTiles");
const GIT_LFS_POINTER_PREFIX = "version https://git-lfs.github.com/spec/";

const PMTILES_ASSETS = [
  "public/saves/save0/cities.pmtiles",
  "public/saves/save0/countries.pmtiles",
  "public/saves/save0/regions.pmtiles",
];

const LFS_TRACKED_ASSETS = [
  "countries.pmtiles",
  ...PMTILES_ASSETS,
];

const readHeader = (assetPath, length) => {
  const absolutePath = path.join(ROOT_DIR, assetPath);
  const descriptor = fs.openSync(absolutePath, "r");
  const header = Buffer.alloc(length);

  try {
    fs.readSync(descriptor, header, 0, length, 0);
    return header;
  } finally {
    fs.closeSync(descriptor);
  }
};

test("LFS-tracked map assets are checked out as real files", () => {
  for (const assetPath of LFS_TRACKED_ASSETS) {
    const header = readHeader(assetPath, GIT_LFS_POINTER_PREFIX.length);

    assert.notEqual(
      header.toString("utf8"),
      GIT_LFS_POINTER_PREFIX,
      `${assetPath} is still a Git LFS pointer. Run git lfs pull before building or testing.`,
    );
  }
});

test("runtime save PMTiles assets are real PMTiles archives", () => {
  for (const assetPath of PMTILES_ASSETS) {
    const header = readHeader(assetPath, PMTILES_MAGIC.length);

    assert.equal(
      header.toString("utf8"),
      PMTILES_MAGIC.toString("utf8"),
      `${assetPath} is not a PMTiles archive. Run git lfs pull before building or testing.`,
    );
  }
});
