import json
import os
import sys
import urllib.error
import urllib.request


def fetch(url: str, timeout: int) -> object:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def index_tree(nodes: list, acc: dict) -> dict:
    for node in nodes:
        cfg = node.get("wmsConfig")
        if cfg:
            ws = cfg.get("geoserverWorkspace") or cfg.get("workspace")
            layer = cfg.get("geoserverLayer")
            if ws and layer:
                acc[node.get("id")] = f"{ws}:{layer}"
        children = node.get("children")
        if isinstance(children, list):
            index_tree(children, acc)
    return acc


def main() -> int:
    base = os.environ["MAPALAB_API_URL"].rstrip("/")
    timeout = int(os.environ.get("MAPALAB_API_TIMEOUT", "10"))

    try:
        order = fetch(f"{base}/layers/initial-order", timeout)
        tree = fetch(f"{base}/layers/tree", timeout)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        print(f"No se pudo leer el catalogo de mapalab ({base}): {exc}", file=sys.stderr)
        return 1

    if not isinstance(order, list) or not isinstance(tree, list):
        print("Respuesta inesperada del catalogo de mapalab.", file=sys.stderr)
        return 1

    by_id = index_tree(tree, {})
    seen = set()
    for layer_id in order:
        entry = by_id.get(layer_id)
        if entry and entry not in seen:
            seen.add(entry)
            print(entry)

    if not seen:
        print("El catalogo no devolvio ninguna capa inicial publicada.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
