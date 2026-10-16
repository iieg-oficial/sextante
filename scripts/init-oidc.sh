#!/bin/bash
set +H
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

GEOSERVER_URL="http://${GEOSERVER_BIND_ADDR:-127.0.0.1}:${GEOSERVER_PORT:-8080}/${GEOSERVER_CONTEXT_ROOT:-sextante}"
source "$SCRIPT_DIR/lib/gs_curl.sh"

FILTRO=minerva
SEC="$GEOSERVER_URL/rest/security"

if [ -z "${OIDC_CLIENT_ID:-}" ] || [ -z "${OIDC_CLIENT_SECRET:-}" ]; then
  echo "OIDC_CLIENT_ID u OIDC_CLIENT_SECRET vacios: sin inicio de sesion con minerva"
  exit 0
fi

: "${OIDC_PUBLIC_URL:?falta OIDC_PUBLIC_URL (issuer que ve el navegador)}"
: "${OIDC_INTERNAL_URL:?falta OIDC_INTERNAL_URL (canal backend para token y JWKS)}"
ROLES="${OIDC_ROLE_MAP:-sextante.administrador=ROLE_ADMINISTRATOR}"

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

filtro_xml() {
  cat <<EOF
<org.geoserver.security.oauth2.config.GeoServerOAuth2LoginFilterConfig>
  <name>$FILTRO</name>
  <className>org.geoserver.security.oauth2.login.GeoServerOAuth2LoginAuthenticationFilter</className>
  <roleSource class="org.geoserver.security.oauth2.config.OpenIdRoleSource">AccessToken</roleSource>
  <oidcEnabled>true</oidcEnabled>
  <oidcClientId>$(xml_escape "$OIDC_CLIENT_ID")</oidcClientId>
  <oidcClientSecret>$(xml_escape "$OIDC_CLIENT_SECRET")</oidcClientSecret>
  <oidcAuthorizationUri>$(xml_escape "${OIDC_PUBLIC_URL%/}/auth/authorize")</oidcAuthorizationUri>
  <oidcTokenUri>$(xml_escape "${OIDC_INTERNAL_URL%/}/auth/token")</oidcTokenUri>
  <oidcUserInfoUri>$(xml_escape "${OIDC_INTERNAL_URL%/}/userinfo")</oidcUserInfoUri>
  <oidcJwkSetUri>$(xml_escape "${OIDC_INTERNAL_URL%/}/.well-known/jwks.json")</oidcJwkSetUri>
  <oidcScopes>openid profile email</oidcScopes>
  <oidcUsePKCE>true</oidcUsePKCE>
  <oidcAuthenticationMethodPostSecret>true</oidcAuthenticationMethodPostSecret>
  <oidcJwsAlgorithmName>RS256</oidcJwsAlgorithmName>
  <oidcUserNameAttribute>email</oidcUserNameAttribute>
  <tokenRolesClaim>roles</tokenRolesClaim>
  <roleConverterString>$(xml_escape "$ROLES")</roleConverterString>
  <onlyExternalListedRoles>false</onlyExternalListedRoles>
  <enableRedirectAuthenticationEntryPoint>false</enableRedirectAuthenticationEntryPoint>
  <enableResourceServerMode>true</enableResourceServerMode>
  <validateTokenAudience>false</validateTokenAudience>
</org.geoserver.security.oauth2.config.GeoServerOAuth2LoginFilterConfig>
EOF
}

if gs_curl -s "$SEC/authfilters/$FILTRO.xml" | grep -q "<name>$FILTRO</name>"; then
  metodo=PUT
  destino="$SEC/authfilters/$FILTRO"
else
  metodo=POST
  destino="$SEC/authfilters"
fi
code=$(filtro_xml | gs_curl -s -o /dev/null -w "%{http_code}" -X "$metodo" \
  -H "Content-Type: application/xml" --data-binary @- "$destino")
if [ "$code" != "200" ] && [ "$code" != "201" ]; then
  echo "✗ No se pudo guardar el filtro $FILTRO ($metodo, HTTP $code)" >&2
  exit 1
fi
echo "  filtro $FILTRO: $metodo $code"

cadena=$(gs_curl -s "$SEC/filterchain/web.xml")
if [ -z "$cadena" ]; then
  echo "✗ No se pudo leer la cadena web" >&2
  exit 1
fi
if printf '%s' "$cadena" | grep -q "<filter>$FILTRO</filter>"; then
  echo "  cadena web: ya tiene $FILTRO"
  exit 0
fi
nueva=$(printf '%s\n' "$cadena" | sed "s#<filter>anonymous</filter>#<filter>$FILTRO</filter>\n    <filter>anonymous</filter>#")
code=$(printf '%s' "$nueva" | gs_curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Content-Type: application/xml" --data-binary @- "$SEC/filterchain/web")
if [ "$code" != "200" ]; then
  echo "✗ No se pudo agregar $FILTRO a la cadena web (HTTP $code)" >&2
  exit 1
fi
echo "  cadena web: $FILTRO antes de anonymous"
