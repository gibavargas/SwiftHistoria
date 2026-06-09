# Legacy Server Reference Notes

`server/` contains the Express server used by the legacy web runtime. It is kept for reference behavior, asset management, and local development of the web client. It is not part of the Swift-native Apple app.

## Main Files

`server.js`

Defines HTTP routes for scenarios, games, runtime JSON assets, uploaded binary assets, export/import, and static `dist` serving.

`libraryStore.js`

Owns filesystem-backed scenario and game catalogs, asset resolution, upload paths, import/export bundle shape, and runtime JSON helpers.

## Route Groups

Scenario routes:

- `GET /api/scenarios`
- `GET /api/scenarios/:scenarioId`
- `POST /api/scenarios`
- `PUT /api/scenarios/:scenarioId`
- `GET /api/scenarios/:scenarioId/export`
- `POST /api/scenarios/import`
- Scenario asset upload, download, and delete routes

Game routes:

- `GET /api/games`
- `GET /api/games/:gameId`
- `POST /api/games`
- `PUT /api/games/active`
- `PUT /api/games/:gameId`
- Game asset upload, download, and delete routes

Runtime asset routes:

- JSON read/write endpoints for browser save files
- Binary range serving for PMTiles and other large assets

## Safety Notes

The upload parsers allow large payloads because map and save bundles can be large. Keep this server local/reference unless a separate hardening pass adds authentication, quota, and deployment controls.

If you change route behavior, also check the browser runtime helpers in `src/runtime/assets.js` and related Node tests.
