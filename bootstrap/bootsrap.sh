#!/bin/sh

set -e

# Default variables
# Check platform arm or x86
if [ "$(uname -m)" = "aarch64" ]; then
  echo "ARM platform detected"
  IMAGE="ghcr.io/laboratory-for-safe-and-secure-systems/estclient:arm"
else
  echo "x86 platform detected"
  IMAGE="ghcr.io/laboratory-for-safe-and-secure-systems/estclient:latest"
fi
SERVER=""
BASE_CERT_PATH="/c/certificates"
CERT_PATH="$BASE_CERT_PATH/pure_chains_existing_keys/secp384" # Path on the container
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

# Function to display usage
usage() {
  echo "Usage: $0 --server <server> [--cert-path <path>] [--image <image>]"
  exit 1
}

# Parse options
OPTIONS=$(getopt -o s:c:i:o:h --long server:,cert-path:,image:,output:,help -- "$@")
if ! eval set -- "$OPTIONS"; then
  usage
fi

eval set -- "$OPTIONS"

# Extract options and their arguments
while true; do
  case "$1" in
    -s|--server)
      SERVER="$2"
      if ! nc -z "$SERVER" 8443 > /dev/null 2>&1; then
        echo "$SERVER is not reachable on port 8443"
        exit 1
      fi
      shift 2
      ;;
    -c|--cert-path)
      CERT_PATH="$BASE_CERT_PATH/$2"
      # Check if this folder exists in the container
      echo "$CERT_PATH"
      if ! docker run --rm -v "$(mktemp -d):$CERT_PATH" "$IMAGE" bash -c "[ -d $CERT_PATH ]"; then
        echo "Error: $CERT_PATH does not exist in the container"
        exit 1
      fi

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
  echo "Pulling EST client image... $IMAGE"
  docker pull "$IMAGE"
}

csr() {
  echo "Generating CSR..."
  docker run --rm -v "$OUTPUT_DIR":/output "$IMAGE" estclient \
    csr \
    -key "$CERT_PATH/client/privateKey.pem" \
    -cn 'KRITIS3M Client' \
    -country "DE" \
    -org "OTH Regensburg" \
    -ou "LaS3" \
    -emails 'kritis3m@oth-regensburg.de' \
    -dnsnames "localhost" \
    -out /output/client.csr \
    -ips 127.0.0.1

  if [ ! -f "$OUTPUT_DIR/client.csr" ]; then
    echo "CSR generation failed"
    exit 1
  fi
  echo "CSR created at $OUTPUT_DIR/client.csr"
}

reenroll() {
  if [ -z "$SERVER" ]; then
    echo "Server not set"
    exit 1
  fi
  echo "Reenrolling... Connecting to $SERVER:8443"
  docker run --rm --network host -v "$OUTPUT_DIR":/output "$IMAGE" estclient \
    reenroll \
    -server "$SERVER:8443" \
    -explicit "$CERT_PATH/root/cert.pem" \
    -certs "$CERT_PATH/client/cert.pem" \
    -key "$CERT_PATH/client/privateKey.pem" \
    -csr /output/client.csr \
    -out /output/client.crt

  if [ ! -f "$OUTPUT_DIR/client.crt" ]; then
    echo "Reenrollment failed"
    exit 1
  fi
  echo "Certificate created at $OUTPUT_DIR/client.crt"
}

echo "Starting script..."
get_client
csr
reenroll
echo "Script completed successfully!"
