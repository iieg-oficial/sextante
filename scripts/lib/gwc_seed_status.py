import json
import sys

ESTADOS = {0: "pendiente", 1: "corriendo", 2: "hecho", -1: "abortado"}


def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        print("GWC no devolvio estado.")
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        print("Respuesta no interpretable de GWC:")
        print(raw[:400])
        return

    tasks = [t for t in (data.get("long-array-array") or []) if len(t) >= 5]
    if not tasks:
        print("Sin tareas de seed en curso.")
        return

    activas = [t for t in tasks if t[1] > 0 and t[4] in (0, 1)]
    if not activas:
        print(f"Sin tareas en curso ({len(tasks)} ya terminada(s); GWC olvida sus contadores).")
        return

    print(f"{'tarea':<20} {'hechos':>12} {'total':>12} {'avance':>8}")
    hechos = total = 0
    for done, tiles, _remaining, task_id, status in (t[:5] for t in activas):
        hechos += done
        total += tiles
        print(f"{'#' + str(task_id) + ' ' + ESTADOS.get(status, str(status)):<20} "
              f"{done:>12,} {tiles:>12,} {done / tiles * 100:>7.1f}%")

    print()
    pct = hechos / total * 100 if total else 0
    print(f"{len(activas)} tarea(s) en curso · {hechos:,} de {total:,} tiles ({pct:.1f}%)")


if __name__ == "__main__":
    main()
