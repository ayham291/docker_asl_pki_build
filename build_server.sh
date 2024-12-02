#!/bin/env bash


if [ "$(uname -m)" = "aarch64" ]; then
  echo "ARM platform detected"
  IMAGE_SCALE="ghcr.io/laboratory-for-safe-and-secure-systems/kritis3m_scale:arm"
  IMAGE_EST="ghcr.io/laboratory-for-safe-and-secure-systems/estserver:arm"
  IMAGE_UI="ghcr.io/laboratory-for-safe-and-secure-systems/ui:arm"
else
  echo "x86 platform detected"
  IMAGE_SCALE="ghcr.io/laboratory-for-safe-and-secure-systems/kritis3m_scale:latest"
  IMAGE_EST="ghcr.io/laboratory-for-safe-and-secure-systems/estserver:latest"
  IMAGE_UI="ghcr.io/laboratory-for-safe-and-secure-systems/ui:latest"
fi

startup() {
  # KRITIS3M_SCALE Configuration
  if [ ! -f "config.yaml" ] || [ ! -f "startup.json" ] || [ ! -f "node_db.sqlite" ]; then
    if command -v wget >/dev/null 2>&1; then
      wget -qO config.yaml https://raw.githubusercontent.com/Laboratory-for-Safe-and-Secure-Systems/kritis3m_scale/refs/heads/main/config.yaml
      wget -qO startup.json https://raw.githubusercontent.com/Laboratory-for-Safe-and-Secure-Systems/kritis3m_scale/refs/heads/main/startup.json
      wget -qO node_db.sqlite https://raw.githubusercontent.com/Laboratory-for-Safe-and-Secure-Systems/kritis3m_scale/refs/heads/main/db.sqlite
    elif command -v curl >/dev/null 2>&1; then
      curl -sSLO config.yaml https://raw.githubusercontent.com/Laboratory-for-Safe-and-Secure-Systems/kritis3m_scale/refs/heads/main/config.yaml
      curl -sSLO startup.json https://raw.githubusercontent.com/Laboratory-for-Safe-and-Secure-Systems/kritis3m_scale/refs/heads/main/startup.json 
      curl -sSLO node_db.sqlite https://raw.githubusercontent.com/Laboratory-for-Safe-and-Secure-Systems/kritis3m_scale/refs/heads/main/db.sqlite
    fi
  fi

# Run Kritis3m Scale
# touch node_db.sqlite
touch node_db.sqlite-shm
touch node_db.sqlite-wal

docker run -d \
  -p 8080:8080 \
  -p 8181:8181 \
  -it \
  --name kritis3m_scale \
  -v "$PWD"/config.yaml:/config.yaml \
  -v "$PWD"/startup.json:/startup.json \
  -v "$PWD"/node_db.sqlite:/db.sqlite \
  -v "$PWD"/node_db.sqlite-shm:/db.sqlite-shm \
  -v "$PWD"/node_db.sqlite-wal:/db.sqlite-wal \
  -v "$PWD"/certs/privateKey.pem:/certs/privateKey.pem \
  -v "$PWD"/certs/kritis3m_scale/chain.pem:/certs/chain.pem \
  $IMAGE_SCALE \
  bash -c "cp /c/certificates/pure_chains_existing_keys/secp384/root/cert.pem /certs/cert.pem && kritis3m_scale --config /config.yaml import && kritis3m_scale --config /config.yaml start"

# EST Server Configuration
touch est_db.sqlite
touch est_db.sqlite-shm
touch est_db.sqlite-wal

docker run -d \
  -p 8443:8443 \
  --name estserver \
  -it \
  -v "$PWD"/config.json:/config.json \
  -v "$PWD"/est_db.sqlite:/test.db \
  -v "$PWD"/est_db.sqlite-shm:/test.db-shm \
  -v "$PWD"/est_db.sqlite-wal:/test.db-wal \
  -v "$PWD"/certs/privateKey.pem:/certs/privateKey.pem \
  -v "$PWD"/certs/kritis3m_est/chain.pem:/certs/chain.pem \
  $IMAGE_EST \
  bash -c "estserver --config /config.json"

# Run UI
docker run -d \
  -p 8888:8080 \
  --name ui \
  -it \
  -v "$PWD"/est_db.sqlite:/est_db.sqlite \
  -v "$PWD"/est_db.sqlite-shm:/est_db.sqlite-shm \
  -v "$PWD"/est_db.sqlite-wal:/est_db.sqlite-wal \
  -v "$PWD"/node_db.sqlite:/node_db.sqlite \
  -v "$PWD"/node_db.sqlite-shm:/node_db.sqlite-shm \
  -v "$PWD"/node_db.sqlite-wal:/node_db.sqlite-wal \
  $IMAGE_UI \
  bash -c "ui -certDB /est_db.sqlite -nodesDB /node_db.sqlite"
}

down_containers() {
  # RM only db caches
  rm -f node_db.sqlite-shm node_db.sqlite-wal est_db.sqlite-shm est_db.sqlite-wal
  docker stop kritis3m_scale estserver ui
  docker rm kritis3m_scale estserver ui
}

args=("$@")
for ((i=0; i<$#; i++)); do
  case ${args[$i]} in
    -s|--startup)
      startup
      ;;
    -d|--down)
      down_containers
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -s, --startup Start the containers"
      echo "  -d, --down    Stop and remove the containers"
      echo "  -h, --help    Display this help message"
      ;;
    *)
      echo "Error: Invalid option"
      ;;
    esac
done
