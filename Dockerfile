docker build -t serv:latest -<<EOF
# Stage 1: Build the binary using a temporary build container
FROM i386/ubuntu:latest AS builder

# Install required tools (nasm and gcc)
RUN apt-get update && \
    apt-get install -y nasm gcc

# Create a writable working directory
WORKDIR /app

RUN echo \
    "section .data\n"\
    "    listen_port equ 8080\n"\
    "    hello_msg db 'HTTP/1.1 200 OK', 0x0D, 0x0A, 'Content-Length: 13', 0x0D, 0x0A, 0x0D, 0x0A, 'Hello, World!', 0\n"\
    "\n"\
    "section .bss\n"\
    "    client_sock resd 1\n"\
    "\n"\
    "section .text\n"\
    "    global my_start\n"\
    "\n"\
    "my_start:\n"\
    "    ; Create a socket\n"\
    "    xor eax, eax\n"\
    "    xor edi, edi\n"\
    "    mov al, 0x66\n"\
    "    mov bl, 0x1\n"\
    "    mov ecx, 0x1\n"\
    "    int 0x80\n"\
    "    mov edi, eax\n"\
    "\n"\
    "    ; Bind the socket to address 0.0.0.0:8080\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x66\n"\
    "    xor ebx, ebx\n"\
    "    mov bl, 0x2\n"\
    "    mov ecx, edi\n"\
    "    mov edx, listen_port\n"\
    "    mov esi, 0x0\n"\
    "    mov edi, 0x10\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Listen for incoming connections\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x66\n"\
    "    mov ebx, edi\n"\
    "    mov ecx, 0x1\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Accept incoming connection\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x66\n"\
    "    mov ebx, edi\n"\
    "    lea ecx, [client_sock]\n"\
    "    lea edx, [edi + 4]\n"\
    "    lea edi, [esp + 4]\n"\
    "    sub esp, 0x10\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Read the request from the client socket (up to 1024 bytes)\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x3\n"\
    "    mov ebx, [client_sock]\n"\
    "    lea ecx, [hello_msg]\n"\
    "    mov edx, 1024\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Send the 'Hello, World!' message to the client\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x4\n"\
    "    mov ebx, [client_sock]\n"\
    "    lea ecx, [hello_msg]\n"\
    "    mov edx, 24\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Close the client socket\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x6\n"\
    "    mov ebx, [client_sock]\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Close the server socket\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x6\n"\
    "    mov ebx, edi\n"\
    "    int 0x80\n"\
    "\n"\
    "    ; Exit the program\n"\
    "    xor eax, eax\n"\
    "    mov al, 0x1\n"\
    "    xor ebx, ebx\n"\
    "    int 0x80\n" \
    > http_server.asm

# Create a simple C file with a main function calling my_start
RUN echo \
    "#include <stdio.h>\n"\
    "extern void my_start();\n"\
    "int main() {\n"\
    "    my_start();\n"\
    "    return 0;\n"\
    "}" \
    > main.c

# Compile both the assembly and C code
RUN nasm -f elf32 http_server.asm -o http_server.o
RUN gcc -m32 -nostartfiles -nodefaultlibs -o http_server main.c http_server.o

# Stage 2: Create a minimal "from scratch" container
FROM scratch

# Copy the compiled binary from the builder stage
COPY --from=builder /app/http_server /http_server

# Expose the port the server is listening on
EXPOSE 8080

# Set the entrypoint to run the HTTP server
ENTRYPOINT ["/http_server"]
EOF
