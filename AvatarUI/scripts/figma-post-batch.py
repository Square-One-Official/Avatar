#!/usr/bin/env python3
"""Post een batch SVG's naar Figma-upload-URL's (van de MCP-tool upload_assets).

  figma-post-batch.py <urls.json> <mapping.json> <svg>...

urls.json = het tool-antwoord ({"uploads":[{"submitUrl":…},…]}); de i-de SVG
gaat naar de i-de URL (parallel). mapping.json krijgt per bestand het
node-id (placedOnNodeId) erbij, zodat een use_figma-script de nodes daarna
kan benoemen en in secties kan leggen.
"""
import json, sys, pathlib, subprocess
from concurrent.futures import ThreadPoolExecutor
urls = [u["submitUrl"] for u in json.load(open(sys.argv[1]))["uploads"]]
mapping_path = pathlib.Path(sys.argv[2])
mapping = json.loads(mapping_path.read_text()) if mapping_path.exists() else {}
files = [pathlib.Path(f) for f in sys.argv[3:]]
assert len(files) <= len(urls), f"{len(files)} bestanden, {len(urls)} URL's"
def post(pair):
    url, f = pair
    r = subprocess.run(["curl", "-s", "-X", "POST", url, "-F", f"file=@{f};type=image/svg+xml"],
                       capture_output=True, text=True)
    try:
        j = json.loads(r.stdout)
    except Exception:
        return f.stem, {"error": r.stdout[:200] or r.stderr[:200]}
    return f.stem, j
with ThreadPoolExecutor(8) as ex:
    for stem, j in ex.map(post, zip(urls, files)):
        if j.get("success"):
            mapping[stem] = j["placedOnNodeId"]
        else:
            print("FOUT", stem, j, file=sys.stderr)
mapping_path.write_text(json.dumps(mapping, indent=1, sort_keys=True))
print(f"{sum(1 for _ in files)} gepost, mapping: {len(mapping)} nodes")
