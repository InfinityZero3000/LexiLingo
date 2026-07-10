import socket
import threading
import sys

def handle_connect(client_socket):
    try:
        # Read the request headers from the client
        request = client_socket.recv(8192).decode('utf-8', errors='ignore')
        if not request:
            client_socket.close()
            return
        
        lines = request.split('\r\n')
        first_line = lines[0]
        words = first_line.split()
        if len(words) < 2:
            client_socket.close()
            return
            
        method, target = words[0], words[1]
        
        if method == 'CONNECT':
            # HTTPS Proxy Connect
            if ':' in target:
                host, port = target.split(':')
                port = int(port)
            else:
                host, port = target, 443
            
            # Connect to target using IPv6 if possible (e.g. YouTube), otherwise fallback to IPv4
            try:
                remote_socket = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
                remote_socket.connect((host, port))
            except Exception:
                try:
                    remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    remote_socket.connect((host, port))
                except Exception as e:
                    print(f"Failed to connect to {host}:{port}: {e}", file=sys.stderr)
                    client_socket.close()
                    return
                
            # Send HTTP 200 Connection Established to client
            client_socket.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        else:
            # Standard HTTP GET/POST Proxy request
            if target.startswith('http://'):
                url_part = target[7:]
                path_idx = url_part.find('/')
                host_part = url_part[:path_idx] if path_idx != -1 else url_part
                path = url_part[path_idx:] if path_idx != -1 else '/'
                if ':' in host_part:
                    host, port = host_part.split(':')
                    port = int(port)
                else:
                    host, port = host_part, 80
            else:
                client_socket.close()
                return
                
            try:
                remote_socket = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
                remote_socket.connect((host, port))
            except Exception:
                try:
                    remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    remote_socket.connect((host, port))
                except Exception as e:
                    print(f"Failed to connect to {host}:{port}: {e}", file=sys.stderr)
                    client_socket.close()
                    return
                
            # Forward the modified request to remote
            new_request = f"{method} {path} HTTP/1.1\r\n"
            for line in lines[1:]:
                if line:
                    new_request += line + "\r\n"
            new_request += "\r\n"
            remote_socket.sendall(new_request.encode('utf-8'))
            
        def forward(src, dst):
            try:
                while True:
                    data = src.recv(8192)
                    if not data:
                        break
                    dst.sendall(data)
            except Exception:
                pass
            finally:
                src.close()
                dst.close()
                
        threading.Thread(target=forward, args=(client_socket, remote_socket), daemon=True).start()
        threading.Thread(target=forward, args=(remote_socket, client_socket), daemon=True).start()
        
    except Exception as e:
        print(f"Proxy error: {e}", file=sys.stderr)
        try:
            client_socket.close()
        except Exception:
            pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', 8888))
    server.listen(100)
    print("HTTPS Proxy listening on port 8888...", file=sys.stderr)
    try:
        while True:
            client_socket, addr = server.accept()
            threading.Thread(target=handle_connect, args=(client_socket,), daemon=True).start()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()

if __name__ == '__main__':
    main()
