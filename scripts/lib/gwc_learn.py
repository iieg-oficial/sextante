import os
import re
import sys
from urllib.parse import parse_qs, unquote_plus, urlsplit

URI_RE = re.compile(r'(?:request_uri"\s*:\s*"|GET\s+)([^"\s]+)')


def extract(line: str) -> tuple[str, str] | None:
    match = URI_RE.search(line)
    if not match:
        return None
    query = parse_qs(urlsplit(unquote_plus(match.group(1))).query, keep_blank_values=True)
    upper = {k.upper(): v for k, v in query.items()}
    layers = upper.get("LAYERS", [""])[0]
    cql = upper.get("CQL_FILTER", [""])[0]
    if not layers or not cql:
        return None
    if ";" in cql or "," in layers:
        return None
    return layers, cql


def main() -> None:
    only = [s for s in os.environ.get("GWC_ONLY", "").split() if s]
    seen: dict[str, set[str]] = {}

    for line in sys.stdin:
        found = extract(line)
        if not found:
            continue
        layer, cql = found
        if only and layer not in only:
            continue
        seen.setdefault(layer, set()).add(cql)

    for layer, values in sorted(seen.items()):
        for value in sorted(values):
            print(f"{layer}={value}")


if __name__ == "__main__":
    main()
