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
SOLO="${OIDC_SOLO:-false}"

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

agregar_a_cadena() {
  local nombre=$1 antes_de=$2 cadena nueva code
  cadena=$(gs_curl -s "$SEC/filterchain/$nombre.xml")
  if ! printf '%s' "$cadena" | grep -q "<filter>$antes_de</filter>"; then
    echo "✗ No se pudo leer la cadena $nombre o no tiene $antes_de" >&2
    return 1
  fi
  if printf '%s' "$cadena" | grep -q "<filter>$FILTRO</filter>"; then
    echo "  cadena $nombre: ya tiene $FILTRO"
    return 0
  fi
  nueva=$(printf '%s\n' "$cadena" | sed "0,/<filter>$antes_de<\/filter>/s##<filter>$FILTRO</filter>\n    <filter>$antes_de</filter>#")
  code=$(printf '%s' "$nueva" | gs_curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Content-Type: application/xml" --data-binary @- "$SEC/filterchain/$nombre")
  if [ "$code" != "200" ]; then
    echo "✗ No se pudo agregar $FILTRO a la cadena $nombre (HTTP $code)" >&2
    return 1
  fi
  echo "  cadena $nombre: $FILTRO antes de $antes_de"
}

formulario() {
  local quiere=$1 web nueva login code
  web=$(gs_curl -s "$SEC/filterchain/web.xml")
  if [ "$quiere" = "false" ] && printf '%s' "$web" | grep -q "<filter>form</filter>"; then
    nueva=$(printf '%s\n' "$web" | sed '/<filter>form<\/filter>/d')
  elif [ "$quiere" = "true" ] && ! printf '%s' "$web" | grep -q "<filter>form</filter>"; then
    nueva=$(printf '%s\n' "$web" | sed "0,/<filter>$FILTRO<\/filter>/s##<filter>form</filter>\n    <filter>$FILTRO</filter>#")
  fi
  if [ -n "${nueva:-}" ]; then
    code=$(printf '%s' "$nueva" | gs_curl -s -o /dev/null -w "%{http_code}" -X PUT \
      -H "Content-Type: application/xml" --data-binary @- "$SEC/filterchain/web")
    [ "$code" = "200" ] || { echo "✗ No se pudo cambiar el formulario en la cadena web (HTTP $code)" >&2; return 1; }
  fi
  login=$(gs_curl -s "$SEC/filterchain/webLogin.xml")
  if [ "$quiere" = "false" ]; then
    nueva=$(printf '%s' "$login" | sed 's/disabled="false"/disabled="true"/')
  else
    nueva=$(printf '%s' "$login" | sed 's/disabled="true"/disabled="false"/')
  fi
  if [ "$nueva" != "$login" ]; then
    code=$(printf '%s' "$nueva" | gs_curl -s -o /dev/null -w "%{http_code}" -X PUT \
      -H "Content-Type: application/xml" --data-binary @- "$SEC/filterchain/webLogin")
    [ "$code" = "200" ] || { echo "✗ No se pudo cambiar la cadena webLogin (HTTP $code)" >&2; return 1; }
  fi
  if [ "$quiere" = "false" ]; then
    echo "  formulario de usuario y contraseña: apagado (solo minerva)"
  else
    echo "  formulario de usuario y contraseña: encendido"
  fi
}

usuarios_locales() {
  local extra
  extra=$(gs_curl -s "$GEOSERVER_URL/rest/security/usergroup/users.json" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(u["userName"] for u in d.get("users", []) if u["userName"] != sys.argv[1]))' \
      "${GEOSERVER_ADMIN_USER:-}" 2>/dev/null)
  if [ -n "$extra" ]; then
    echo "  ! usuarios locales además del admin: $extra (los accesos se dan con roles de minerva)"
  fi
}

agregar_a_cadena web anonymous || exit 1
agregar_a_cadena rest basic || exit 1
if [ "$SOLO" = "true" ]; then
  formulario false || exit 1
else
  formulario true || exit 1
fi
usuarios_locales
