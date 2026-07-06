#!/usr/bin/env python3
"""
Very simple HTTP file server in python
Usage::
    ./server.py [<port>]
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
import mimetypes
import os
import pathlib

cwd = "/var/http/root" #os.path.normcase(os.getcwd())
class ThreadingSimpleServer(ThreadingMixIn, HTTPServer):
   pass

class S(BaseHTTPRequestHandler):
    def __init__(self, *args, directory=None, **kwargs):
        self.protocol_version = 'HTTP/1.1'
        super().__init__(*args, **kwargs)

    def _send_response(self, code = 200, msg=b'Done', content_type='text/plain'):
        body = msg
        self.send_response(code)
        if body:
           self.send_header('Content-type', content_type)
           self.send_header('Content-Length', len(body))
        self.end_headers()
        if body:
           self.wfile.write(body)
#        self.wfile.close()

    def req_path(self):
        fname = self.path[1:] # Strip leading slash
        path = os.path.normcase(os.path.dirname(os.path.realpath(fname)))
        if os.path.commonpath((path, cwd)) == cwd:
            return fname
        raise Exception("Access denied")

    def do_GET(self):
        try:
            with open(self.req_path(), "rb") as src:
                self._send_response(200, src.read(), mimetypes.guess_type(self.req_path()))
        except FileNotFoundError as ex:
            self._send_response(404, b'404 Not Found\r\n')

    def do_HEAD(self):
            path = self.req_path()
            if not os.path.exists(path):
              self._send_response(404, None, 'text/plain')
            else:
              self._send_response(200, None, 'text/plain')

    def do_PUT(self):
         try:
            path = self.req_path()
            pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
            with open(path, "wb") as dst:
                content_length = int(self.headers['Content-Length'])
                dst.write(self.rfile.read(content_length))
            self._send_response(200, b'Done\r\n')
         except Exception as ex:
            print(ex)
            self._send_response(500, b'500 Access Denied\r\n')

    def do_POST(self):
        return self.do_PUT()

def run(port=8000):
    server_address = ('', port)
    httpd = ThreadingSimpleServer(server_address, S)
    print(f'Listening on port {port}')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == '__main__':
    from sys import argv
    os.chdir(cwd)
    if len(argv) == 2:
        run(port=int(argv[1]))
    else:
        run()
