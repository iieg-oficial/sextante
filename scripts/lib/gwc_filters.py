import os
import re
import sys
from xml.sax.saxutils import escape

FILTER_TPL = """    <stringParameterFilter>
      <key>%s</key>
      <defaultValue>%s</defaultValue>
      <values>
%s
      </values>
    </stringParameterFilter>"""


def build_filter(key: str, default: str, values: list[str]) -> str:
    body = "\n".join("        <string>%s</string>" % escape(v) for v in values)
    return FILTER_TPL % (escape(key), escape(default), body)


def main() -> None:
    xml = os.environ["GWC_XML"]
    cql = os.environ.get("CQL", "")
    env_values = os.environ["ENV_VALUES"].split(",")
    env_default = os.environ["ENV_DEFAULT"]

    xml = re.sub(
        r"\s*<stringParameterFilter>\s*<key>(?:ENV|CQL_FILTER)</key>.*?</stringParameterFilter>",
        "",
        xml,
        flags=re.S,
    )

    xml = re.sub(r'(<allowedStyles) class="[^"]*"', r"\1", xml)
    xml = re.sub(r"<parameterFilters\s*/>", "<parameterFilters>\n  </parameterFilters>", xml)

    blocks = [build_filter("ENV", env_default, env_values)]

    cql_values = [v for v in cql.split("\x1f") if v]
    if cql_values:
        blocks.append(build_filter("CQL_FILTER", "", cql_values))

    joined = "\n".join(blocks)
    if "<parameterFilters>" in xml:
        xml = xml.replace("</parameterFilters>", joined + "\n  </parameterFilters>", 1)
    else:
        xml = xml.replace(
            "</GeoServerLayer>",
            "  <parameterFilters>\n" + joined + "\n  </parameterFilters>\n</GeoServerLayer>",
            1,
        )

    sys.stdout.write(xml)


if __name__ == "__main__":
    main()
