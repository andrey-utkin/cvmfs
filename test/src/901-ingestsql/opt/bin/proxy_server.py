#!/usr/bin/env python3

import http.server
import socketserver
from socketserver import ThreadingMixIn
import requests
import time
import socket
import struct

class ProxyHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        try:
            # Forward the GET request to the target server
            print(f"Received HEAD request for {self.path}")
            response = requests.head(self.path, headers=self.headers)

            # Send response status and headers
            self.send_response(response.status_code)
            for header, value in response.headers.items():
                self.send_header(header, value)
            self.end_headers()

            # Send response content
            self.wfile.write(response.content)
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")


    def do_GET(self):
        try:
            # Forward the GET request to the target server
            print(f"Received GET request for {self.path}")
            response = requests.get(self.path, headers=self.headers)

            # Send response status and headers
            self.send_response(response.status_code)
            for header, value in response.headers.items():
                self.send_header(header, value)
            self.end_headers()

            # Send response content
            self.wfile.write(response.content)
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")

    def do_PUT(self):
        try:
            # Read the content length to get the body of the POST request
            content_length = int(self.headers.get('Content-Length', 0))
            post_body = self.rfile.read(content_length)

            # Forward the POST request to the target server
            print(f"Received PUT request for {self.path}")
            response = requests.put(self.path, data=post_body, headers=self.headers)

            # Send response status and headers
            self.send_response(response.status_code)
            for header, value in response.headers.items():
                self.send_header(header, value)
            self.end_headers()

            # Send response content
            self.wfile.write(response.content)
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")


    def do_POST(self):
        try:
            # Read the content length to get the body of the POST request
            content_length = int(self.headers.get('Content-Length', 0))
            post_body = self.rfile.read(content_length)

            # Forward the POST request to the target server
            print(f"Received POST request for {self.path}")
            response = requests.post(self.path, data=post_body, headers=self.headers)

            # Send response status and headers
            self.send_response(response.status_code)
            for header, value in response.headers.items():
                self.send_header(header, value)
            self.end_headers()

            # Send response content
            self.wfile.write(response.content)
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")

class CustomTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

    def server_bind(self):
        # Set SO_LINGER before binding
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
        super().server_bind()

class ThreadingSimpleServer(ThreadingMixIn, CustomTCPServer):
   pass


def run_proxy_server(host='127.0.0.1', port=8088):
    with ThreadingSimpleServer((host, port), ProxyHTTPRequestHandler) as httpd:
        print(f"Serving HTTP Proxy on {host}:{port} with SO_LINGER enabled")
        httpd.serve_forever()


if __name__ == "__main__":
    run_proxy_server()
