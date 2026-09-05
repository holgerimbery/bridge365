# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Converts a YAML file (e.g. openapi.yaml) to JSON, used by
# deploy-connector.ps1 because paconn's --api-def only accepts JSON.
#
# Usage: python _yaml_to_json.py <input.yaml> <output.json>

import json
import sys

try:
    import yaml
except ImportError:
    print("pyyaml is required: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

if len(sys.argv) != 3:
    print("Usage: python _yaml_to_json.py <input.yaml> <output.json>", file=sys.stderr)
    sys.exit(1)

input_path, output_path = sys.argv[1], sys.argv[2]

with open(input_path, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)