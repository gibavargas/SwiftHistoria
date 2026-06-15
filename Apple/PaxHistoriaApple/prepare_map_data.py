#!/usr/bin/env python3
import urllib.request
import json
import ssl
import os
import sys

# Disable SSL verification to prevent issues on macOS python setups
ssl._create_default_https_context = ssl._create_unverified_context

DATASETS = {
    "land": "https://d2ad6b4ur7yvpq.cloudfront.net/naturalearth-3.3.0/ne_50m_land.geojson",
    "countries": "https://d2ad6b4ur7yvpq.cloudfront.net/naturalearth-3.3.0/ne_50m_admin_0_countries.geojson",
    "states": "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_1_states_provinces_lakes.geojson",
    "cities": "https://d2ad6b4ur7yvpq.cloudfront.net/naturalearth-3.3.0/ne_50m_populated_places.geojson"
}

def round_coords(coords):
    if not coords:
        return coords
    if isinstance(coords[0], list):
        return [round_coords(c) for c in coords]
    else:
        # Round lon/lat to 4 decimal places (~11 meters precision)
        return [round(coords[0], 4), round(coords[1], 4)]

def process_dataset(name, url, dest_dir):
    print(f"Downloading {name} from {url}...")
    try:
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'}
        )
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"Error downloading {name}: {e}")
        sys.exit(1)

    print(f"Processing {name} (original feature count: {len(data['features'])})...")
    cleaned_features = []

    for feature in data["features"]:
        geom = feature.get("geometry")
        if not geom:
            continue
        
        # Clean coordinates
        geom["coordinates"] = round_coords(geom["coordinates"])
        
        # Clean properties based on dataset type
        # Normalize all property keys to lowercase for uniform access
        props = {k.lower(): v for k, v in feature.get("properties", {}).items()}
        cleaned_props = {}

        if name == "land":
            # Landmasses do not need detailed properties
            cleaned_props["id"] = f"lm_{len(cleaned_features)}"

        elif name == "countries":
            # Keep name, adm0_a3, and continent
            cleaned_props["name"] = props.get("name") or props.get("name_long")
            cleaned_props["id"] = props.get("adm0_a3") or props.get("iso_a3")
            cleaned_props["continent"] = props.get("continent")
        
        elif name == "states":
            # Keep state name, country code, and division code
            name_val = props.get("name") or "Unknown State"
            cleaned_props["name"] = name_val
            country_id = props.get("adm0_a3") or props.get("iso_a3") or props.get("sr_adm0_a3") or "UNK"
            cleaned_props["country_id"] = country_id
            
            # Formulate a clean, unique ID: [COUNTRY]_[STATE_NAME]
            # Strip accents and normalize special characters
            import unicodedata
            normalized_name = unicodedata.normalize('NFKD', name_val).encode('ASCII', 'ignore').decode('utf-8')
            clean_name = ''.join(c if c.isalnum() or c == '_' else '_' for c in normalized_name)
            while '__' in clean_name:
                clean_name = clean_name.replace('__', '_')
            clean_name = clean_name.strip('_').replace(' ', '_')
            
            cleaned_props["id"] = f"{country_id}_{clean_name}"

        elif name == "cities":
            # Keep name, country code, population, and capital status
            cleaned_props["name"] = props.get("name")
            cleaned_props["country_id"] = props.get("adm0_a3") or props.get("iso_a3") or props.get("sr_adm0_a3") or "UNK"
            # Convert pop estimates safely
            pop = props.get("pop_max") or props.get("pop_min") or props.get("pop10") or 0
            cleaned_props["pop"] = int(pop)
            feature_class = props.get("featureclass") or props.get("featurecla") or ""
            cleaned_props["is_capital"] = bool(feature_class.lower() == "admin-0 capital" or props.get("adm0cap") == 1)

            # Filter out very small towns to keep UI uncluttered, except capitals
            if cleaned_props["pop"] < 50000 and not cleaned_props["is_capital"]:
                continue
        
        cleaned_feature = {
            "type": "Feature",
            "geometry": geom,
            "properties": cleaned_props
        }
        cleaned_features.append(cleaned_feature)

    # Sort cities by population so the renderer can easily draw largest first
    if name == "cities":
        cleaned_features.sort(key=lambda x: x["properties"]["pop"], reverse=True)

    cleaned_data = {
        "type": "FeatureCollection",
        "features": cleaned_features
    }

    dest_path = os.path.join(dest_dir, f"{name}.geojson")
    with open(dest_path, "w", encoding="utf-8") as f:
        json.dump(cleaned_data, f, ensure_ascii=False, separators=(',', ':'))

    print(f"Saved optimized {name}.geojson to {dest_path} (features: {len(cleaned_features)}, size: {os.path.getsize(dest_path)/1024:.1f} KB)")

def main():
    dest_dir = os.path.dirname(os.path.abspath(__file__))
    print(f"Destination directory: {dest_dir}")
    
    for name, url in DATASETS.items():
        process_dataset(name, url, dest_dir)
    print("All datasets processed successfully!")

if __name__ == "__main__":
    main()
