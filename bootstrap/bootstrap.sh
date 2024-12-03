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
SCRIPT_DIR=$(dirname "$0")
SERVER=""
CURL=false
CLIENT="docker run --rm --network host -v $OUTPUT_DIR:/output $IMAGE estclient"
BASE_CERT_PATH="/c/certificates"
CERT_ALGO="secp384"
CERT_TYPE="pure_chains_existing_keys/$CERT_ALGO"
CERT_PATH="$BASE_CERT_PATH/$CERT_TYPE/client" # Path on the container
ROOT_CERT_PATH="$BASE_CERT_PATH/$CERT_TYPE/root" # Path on the container
PRIVATE_KEY="privateKey.pem"
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
OPTIONS=$(getopt -o s:c:i:o:qh --long server:,cert-path:,common-name:,root:,client:,image:,output:,pqc,help -- "$@")
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
      if [ "$CLIENT" = "curl" ]; then
        CURL=true
      fi
      shift 2
      ;;
    --common-name)
      COMMON_NAME_EXT="$2"
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
        if [ ! -d "$CERT_PATH" ] || [ ! -f "$CERT_PATH/privateKey.pem" ]; then
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
    -q|--pqc)
      PRIVATE_KEY="privateKey-pqc.pem"
      shift
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

CERT="$out_arg/cert.pem"
INITIAL_CERT="$SCRIPT_DIR"/cert/cert"$COMMON_NAME_EXT".pem

if [ -z "$ROOT_CERT_PATH" ]; then
  ROOT_CERT_PATH="$SCRIPT_DIR"/cert/intemediate/"$CERT_ALGO"
fi
if [ -z "$CERT_PATH" ]; then
  CERT_PATH="$SCRIPT_DIR/cert"
  if [ ! -d "$CERT_PATH" ]; then
    echo "Error: $CERT_PATH does not exist"
    exit 1
  fi
fi

csr() {
  if [ -z "$COMMON_NAME_EXT" ]; then
    COMMON_NAME="KRITIS3M Client"
  else
    COMMON_NAME="KRITIS3M Client - $COMMON_NAME_EXT"
  fi
  echo "Generating CSR..."
  if [ $PRIVATE_KEY = "privateKey-pqc.pem" ]; then
    CSR_PATH="$out_arg/client-pqc$COMMON_NAME_EXT.csr"
  else
    CSR_PATH="$out_arg/client$COMMON_NAME_EXT.csr"
  fi

  if [ ! -f "$CSR_PATH" ]; then
    kritis3m_pki --entity_key "$SCRIPT_DIR"/cert/"$PRIVATE_KEY" \
      --issuer_key "$SCRIPT_DIR"/cert/"$PRIVATE_KEY" \
      --csr_out "$CSR_PATH" \
      --validity 365 \
      --common_name "$COMMON_NAME" \
      --org "OTH Regensburg" \
      --unit "LaS3" \
      --alt_names_DNS "localhost" \
      --alt_names_IP "127.0.0.1"

  echo "CSR created at $CSR_PATH"
  fi

  if [ ! -f "$CSR_PATH" ]; then
    echo "CSR generation failed"
    exit 1
  fi

  echo "Creating client certificate..."
  if [ ! -f "$INITIAL_CERT" ]; then
    # DONT GENERATE PQC CERTIFICATE
    # cannot use it to connect to the server for reenrollment
    kritis3m_pki \
      --entity_key "$SCRIPT_DIR"/cert/privateKey.pem \
      --issuer_key "$ROOT_CERT_PATH"/privateKey.pem \
      --issuer_cert "$ROOT_CERT_PATH"/cert.pem \
      --cert_out "$INITIAL_CERT" \
      --csr_in "$CSR_PATH"

    echo "KRIITS3M Client certificate created at $INITIAL_CERT"
  fi

  if [ ! -f "$INITIAL_CERT" ]; then
    echo "Certificate generation failed"
    exit 1
  fi
}

reenroll() {
  if [ -z "$SERVER" ]; then
    echo "Server not set"
    exit 1
  fi
  echo "Reenrolling... Connecting to $SERVER:8443"
  if ! $CURL; then
    $CLIENT \
      reenroll \
      -server "$SERVER:8443" \
      -explicit "$ROOT_CERT_PATH/cert.pem" \
      -certs "$CERT_PATH/cert$COMMON_NAME_EXT.pem" \
      -key "$CERT_PATH/privateKey.pem" \
      -csr "$CSR_PATH" \
      -out "$CERT"

  elif command -v curl > /dev/null; then
    echo "Using curl to reenroll the certificate..."
    echo "$CURL"
    curl -X POST "https://$SERVER:8443/.well-known/est/simplreenroll" \
      --cacert "$ROOT_CERT_PATH/cert.pem" \
      --cert "$CERT_PATH/cert$COMMON_NAME_EXT.pem" \
      --key "$CERT_PATH/privateKey.pem" \
      --data-binary "@$CSR_PATH" \
      --output "$CERT"

  else
    echo "Error: curl is required to reenroll the certificate"
    exit 1
  fi

  cat "$CERT_PATH/cert$COMMON_NAME_EXT.pem" "$ROOT_CERT_PATH/cert.pem" > "$out_arg/chain.pem"
  echo "Certificate reenrolled at $out_arg/chain.pem"
}

echo "Starting script..."
get_client
csr
reenroll
echo "Script completed successfully!"
