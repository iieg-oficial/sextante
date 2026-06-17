import http.server
import urllib.request
import urllib.error
import os

GEOSERVER = 'http://10.25.7.17:8080'
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE_DIR, **kwargs)

    def do_GET(self):
        if self.path.startswith('/geoserver/'):
            self.proxy_request()
        else:
            super().do_GET()

    def proxy_request(self):
        target_url = GEOSERVER + self.path
        try:
            req = urllib.request.Request(target_url)
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', '*')
                content_type = resp.headers.get('Content-Type', 'application/octet-stream')
                self.send_header('Content-Type', content_type)
                if 'Content-Encoding' in resp.headers:
                    self.send_header('Content-Encoding', resp.headers['Content-Encoding'])
                self.end_headers()
                self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 8087), ProxyHandler)
    print('Proxy corriendo en http://10.25.7.17:8087/visor_vector_tiles.html')
    server.serve_forever()
