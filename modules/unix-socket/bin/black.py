import difflib
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, HTTPServer
import requests
from rich.console import Console
from rich.panel import Panel

console = Console()

def color_status_code(code):
    if 200 <= code < 300:
        return f"[green]{code}[/]"
    elif 300 <= code < 400:
        return f"[cyan]{code}[/]"
    elif 400 <= code < 500:
        return f"[yellow]{code}[/]"
    elif code >= 500:
        return f"[bold red]{code}[/]"
    return str(code)

def extract_error_snippet(body_text):
    lowered = body_text.lower()
    keywords = ['error', 'exception', 'traceback', 'fatal', 'stack trace']
    for kw in keywords:
        if kw in lowered:
            start = lowered.find(kw)
            snippet_start = max(0, start - 50)
            snippet_end = min(len(body_text), start + 150)
            snippet = body_text[snippet_start:snippet_end]
            return snippet
    return None

def compare_responses(virgin, modified):
    diff = difflib.unified_diff(
        virgin.splitlines(),
        modified.splitlines(),
        fromfile='virgin',
        tofile='modified',
        lineterm=''
    )
    return '\n'.join(diff)

def guess_function(path, query_params):
    func = path.strip('/').split('/')[-1] or 'index'
    args = ', '.join(query_params.keys())
    return f"{func}({args})" if args else f"{func}()"

class PentestProxyHandler(BaseHTTPRequestHandler):
    def do_ANY(self):
        url = self.path if self.path.startswith('http') else f"http://{self.headers['Host']}{self.path}"
        parsed = urlparse(url)
        target_port = parsed.port or (443 if parsed.scheme == 'https' else 80)

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length else None

        headers = dict(self.headers)
        headers.pop('Host', None)

        # Only verbose debug if port == 8000
        if target_port != 8000:
            # Silent proxy forwarding
            resp = requests.request(
                method=self.command,
                url=url,
                headers=headers,
                data=body,
                verify=False,
                allow_redirects=False
            )
            self.send_response(resp.status_code)
            for k, v in resp.headers.items():
                if k.lower() != 'content-encoding':
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(resp.content)
            return

        # === FULL DEBUG MODE for port 8000 ===
        query = parse_qs(parsed.query)
        virgin_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"

        console.rule(f"[bold cyan]Captured Request: {self.command} {url}")
        console.print(Panel.fit(f"[bold yellow]Request Headers[/]:\n{headers}"))
        if body:
            console.print(Panel.fit(f"[bold green]Request Body:[/]\n{body.decode(errors='ignore')}"))

        try:
            real_response = requests.request(
                method=self.command,
                url=url,
                headers=headers,
                data=body,
                verify=False,
                allow_redirects=False
            )

            virgin_response = requests.get(virgin_url, headers=headers, verify=False)

            diff = compare_responses(virgin_response.text, real_response.text)
            guessed = guess_function(parsed.path, query)

            console.print(f"[bold green]Guessed Function:[/] [italic]{guessed}")
            if diff:
                console.print(Panel.fit(diff, title="[bold red]Response Diff Detected"))

            status = real_response.status_code
            colored_status = color_status_code(status)
            console.print(f"[magenta]Response Status:[/] {colored_status}")

            if status >= 500:
                error_snippet = extract_error_snippet(real_response.text)
                if error_snippet:
                    console.print(Panel.fit(f"[bold red]Internal Server Error Details:\n{error_snippet}"))
                else:
                    console.print("[bold red]Internal Server Error detected, but no error details found in body.")

            self.send_response(real_response.status_code)
            for k, v in real_response.headers.items():
                if k.lower() != 'content-encoding':
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(real_response.content)

        except Exception as e:
            self.send_error(500, f"Proxy error: {str(e)}")

    def do_GET(self): self.do_ANY()
    def do_POST(self): self.do_ANY()
    def do_PUT(self): self.do_ANY()
    def do_DELETE(self): self.do_ANY()
    def do_PATCH(self): self.do_ANY()
    def do_OPTIONS(self): self.do_ANY()

def run_proxy(port=8888):
    console.print(f"[bold green]🛡️ Pentest Debug Proxy listening on http://127.0.0.1:{port}")
    server = HTTPServer(('0.0.0.0', port), PentestProxyHandler)
    server.serve_forever()

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8888
    run_proxy(port)
