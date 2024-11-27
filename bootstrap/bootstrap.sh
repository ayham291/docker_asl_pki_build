#!/bin/sh

set -e

# Default variables
# Check platform arm or x86
if [ "$(uname -m)" = "aarch64" ]; then
  echo "ARM platform detected"
  IMAGE="ghcr.io/laboratory-for-safe-and-secure-systems/estclient:arm"
  CLIENT_URL="https://github.com/Laboratory-for-Safe-and-Secure-Systems/est/releases/download/v1.0.0/estclient-aarch64"
else
  echo "x86 platform detected"
  IMAGE="ghcr.io/laboratory-for-safe-and-secure-systems/estclient:latest"
  CLIENT_URL="https://github.com/Laboratory-for-Safe-and-Secure-Systems/est/releases/download/v1.0.0/estclient-x86-64"
fi
SERVER=""
CLIENT="docker run --rm --network host -v $OUTPUT_DIR:/output $IMAGE estclient"
BASE_CERT_PATH="/c/certificates"
CERT_TYPE="pure_chains_existing_keys/secp384"
CERT_PATH="$BASE_CERT_PATH/$CERT_TYPE/client" # Path on the container
ROOT_CERT_PATH="$BASE_CERT_PATH/$CERT_TYPE/root" # Path on the container
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

# Function to display usage
usage() {
  echo "Usage: $0 --server <server> [--cert-path <path>] [--image <image>]"
  echo "       $0 --extract-client <path>"
  echo "       $0 --server <server> --client <client> --cert-path <path> [--output-dir <path>]"
  echo "  --server, -s     <server>    EST server address"
  echo "  --client, -c     <client>    EST client command | if specified, then define --cert-path"
  echo "  --cert-path                  Path to the certificates base directory"
  echo "  --root           <root>      Root certificate path"
  echo "  --image, -i      <image>     Docker image to use"
  echo "  --output-dir, -o <path>      Output directory for the client certificate"
  echo "  --extract-client, -e         Extract the estclient binary from the image"
  echo "  --help, -h                   Display this help message"
  echo "Using estclient on its own like:"
  echo "      estclient csr -key <key> -cn <cn> -country <country> -org <org> -ou <ou> -emails <emails> -dnsnames <dnsnames> -ips <ips> -out <out>"
  echo "      estclient reenroll -server <server> -explicit <explicit> -certs <certs> -key <key> -csr <csr> -out <out>"
  exit 1
}

for arg in "$@"; do
  if [ "$arg" = "--extract-client" ] || [ "$arg" = "-e" ]; then
    shift
    if [ -z "$1" ]; then
      echo "Error: --extract-client requires a path argument."
      exit 1
    fi
    OUTPUT_CLIENT="$1"
    echo "Extracting estclient to $OUTPUT_CLIENT"
    docker run --rm -v "$OUTPUT_CLIENT":/output "$IMAGE" bash -c "cp \$(which estclient) /output && chmod +x /output/estclient && chown $(id -u):$(id -g) /output/estclient"
    exit 0
  fi
  if [ "$arg" = "--client" ] || [ "$arg" = "-c" ]; then
    # Remove default CERT_PATH
    CERT_PATH=""
  fi
done

# Parse options
OPTIONS=$(getopt -o s:c:i:o:h --long server:,cert-path:,root:,client:,image:,output:,help -- "$@")
if ! eval set -- "$OPTIONS"; then
  usage
fi

eval set -- "$OPTIONS"

# Extract options and their arguments
while true; do
  case "$1" in
    -s|--server)
      SERVER="$2"
      if ! timeout 1 bash -c "echo > /dev/null 2>&1 < /dev/tcp/$SERVER/8443"; then
        echo "$SERVER is not reachable on port 8443"
        exit 1
      fi
      shift 2
      ;;
    -c|--client)
      CLIENT=$(pwd)/$2
      
      if [ -z "$CERT_PATH" ]; then
        echo "Error: --cert-path is required if --client is specified"
        exit 1
      fi

      shift 2
      ;;
    --cert-path)
      CERT_PATH="$BASE_CERT_PATH/$2"
      if [ "$CLIENT" = "docker run --rm --network host -v $OUTPUT_DIR:/output $IMAGE estclient" ]; then
        echo "Checking if $CERT_PATH exists in the container..."
        if ! docker run --rm "$IMAGE" bash -c "[ -d $CERT_PATH ]"; then
          echo "Error: $CERT_PATH does not exist in the container"
          exit 1
        fi
      else
        CERT_PATH=$2
        if [ ! -d "$CERT_PATH" ] || [ ! -f "$CERT_PATH/cert.pem" ] || [ ! -f "$CERT_PATH/privateKey.pem" ]; then
          echo "Error: $CERT_PATH does not exist or is missing cert.pem or privateKey.pem"
          exit 1
        fi
      fi
      echo "$CERT_PATH"
      shift 2
      ;;
    --root)
      ROOT_CERT_PATH="$BASE_CERT_PATH/$2"
      if [ "$CLIENT" = "docker run --rm --network host -v $OUTPUT_DIR:/output $IMAGE estclient" ]; then
        echo "Checking if $ROOT_CERT_PATH exists in the container..."
        if ! docker run --rm "$IMAGE" bash -c "[ -d $ROOT_CERT_PATH ]"; then
          echo "Error: $ROOT_CERT_PATH does not exist in the container"
          exit 1
        fi
      else
        ROOT_CERT_PATH=$2
        if [ ! -d "$ROOT_CERT_PATH" ] || [ ! -f "$ROOT_CERT_PATH/cert.pem" ]; then
          echo "Error: $ROOT_CERT_PATH does not exist or is missing cert.pem"
          exit 1
        fi
      fi
      echo "$ROOT_CERT_PATH"
      shift 2
      ;;
    -i|--image)
      IMAGE="$2"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      if [ ! -d "$OUTPUT_DIR" ]; then
        echo "Error: $OUTPUT_DIR does not exist"
        exit 1
      fi
      trap - EXIT
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      usage
      ;;
  esac
done

# Validate required arguments
if [ -z "$SERVER" ]; then
  echo "Error: --server is required"
  usage
fi

get_client() {
  if [ -f "$CLIENT" ]; then
    echo "EST client already exists at $CLIENT"
    return
  fi

  if [ "$CLIENT" = "docker run --rm --network host -v $OUTPUT_DIR:/output $IMAGE estclient" ]; then
    echo "Pulling EST client image... $IMAGE"
    docker pull "$IMAGE"
  else
    if command -v wget > /dev/null; then
      echo "Downloading EST client with wget... $CLIENT_URL"
      wget -qO "$CLIENT" "$CLIENT_URL"
    elif command -v curl > /dev/null; then
      echo "Downloading EST client with curl... $CLIENT_URL"
      curl -so "$CLIENT" -L "$CLIENT_URL"
    else
      echo "Error: wget or curl is required to download the client"
      exit 1
    fi
    chmod +x "$CLIENT"
    fi
  if [ ! -f "$CLIENT" ]; then
    echo "Error: Failed to download the client"
    exit 1
  fi
}

if [ "$CLIENT" = "docker run --rm --network host -v $OUTPUT_DIR:/output $IMAGE estclient" ]; then
  out_arg="/output"
else
  out_arg="$OUTPUT_DIR"
  trap - EXIT
fi

get_root_cert() {
  echo "Getting root certificate..."
  ROOT_CERT="$out_arg/ca.pem"
  $CLIENT \
    cacerts \
    -server "$SERVER:8443" \
    -explicit "$ROOT_CERT_PATH/cert.pem" \
    -certs "$CERT_PATH/chain.pem" \
    -key "$CERT_PATH/privateKey.pem" \
    -out "$ROOT_CERT"

  if [ ! -f "$ROOT_CERT" ]; then
    echo "Failed to get root certificate"
    exit 1
  fi
  echo "Root certificate created at $ROOT_CERT"
}

csr() {
  echo "Generating CSR..."
  CSR_PATH="$out_arg/client-$(date +%s).csr"
  $CLIENT \
    csr \
    -key "$CERT_PATH/privateKey.pem" \
    -cn 'KRITIS3M Client' \
    -country "DE" \
    -org "OTH Regensburg" \
    -ou "LaS3" \
    -emails 'kritis3m@oth-regensburg.de' \
    -dnsnames "localhost" \
    -ips 127.0.0.1 \
    -out "$CSR_PATH"

  if [ ! -f "$CSR_PATH" ]; then
    echo "CSR generation failed"
    exit 1
  fi
  echo "CSR created at $CSR_PATH"
}

reenroll() {
  if [ -z "$SERVER" ]; then
    echo "Server not set"
    exit 1
  fi
  echo "Reenrolling... Connecting to $SERVER:8443"
  CERT="$out_arg/cert.pem"
  $CLIENT \
    reenroll \
    -server "$SERVER:8443" \
    -explicit "$ROOT_CERT" \
    -certs "$CERT_PATH/chain.pem" \
    -key "$CERT_PATH/privateKey.pem" \
    -csr "$CSR_PATH" \
    -out "$CERT"

  if [ ! -f "$CERT" ]; then
    echo "Reenrollment failed"
    exit 1
  fi

  cat "$CERT" "$ROOT_CERT" > "$out_arg/chain.pem"
  echo "Certificate created at $CERT"
}

echo "Starting script..."
get_client
get_root_cert
csr
reenroll
echo "Script completed successfully!"
