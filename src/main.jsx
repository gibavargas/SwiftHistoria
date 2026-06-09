// Reference-only web prototype: SwiftHistoria product work belongs in the
// Swift-native Apple implementation under Apple/. Use this tree for inspiration
// or behavior comparison only unless a task explicitly targets the web app.
import { createRoot } from "react-dom/client";
import { configureMapRuntime } from "./runtime/assets.js";
import App from "./App.jsx";
import "maplibre-gl/dist/maplibre-gl.css";
import "./styles.css";

configureMapRuntime();

createRoot(document.getElementById("root")).render(
  <App />,
);
