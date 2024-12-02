# Running the Script with a Local EST-Client

To execute the script using a local `estclient`, use the following command
structure:

```bash
bootstrap.sh \
    --server <SERVER> \
    -c estclient \
    --root <PATH-TO-ROOT> \
    [--cert-path <ENTITY-CERT-PATH>] \
    [--common-name <COMMON-NAME>] \
    [-o <OUTPUT-DIR>] \
    [--pqc]
```

### Required Setup Before Running

Before executing the script, ensure the following directories and files are
prepared:

1. **`cert` Directory**:  
   Create a directory named `cert` in the same location as the script.

2. **Intermediate Certificates Directory**:  
   Create a subdirectory `cert/intermediate/<ALGO>` in the `cert` directory.
   This directory should include:
   - `cert.pem` (Certificate of the root CA)
   - `privateKey.pem` (Private key of the root CA)

3. **Entity Private Keys**:  
   Add the following files for your entity(ies) in the `cert` directory:
   - `privateKey.pem`: Standard private key
   - `privateKey-pqc.pem`: Post-quantum cryptography private key (if using PQC
     mode)

These files will be used for creating all certificates and Certificate Signing
Requests (CSRs) for different entities.

### Inner Workings of the Script

1. **CSR and Certificate Creation**:  
   The script uses the `kritis3m_pki` CLI tool to generate a Certificate
   Signing Request (CSR) and a certificate from the root CA.

2. **Server Interaction**:  
   The CSR is sent to the specified EST server. The script then re-enrolls the
   certificate.

----

## Required Options

- **Client Path (`client`)**:  
  This option is mandatory and must point to the path where the `<estclient>`
  file will be downloaded. Provide the desired path (e.g., `<PATH>/estclient`)
  when running the script. Any valid path is acceptable.

## Optional Options

- **Certificate Path (`cert-path`)**:  
  If not specified, the script will default to using a directory named `cert`
  located in the same directory as the script.

- **Root Certificate (`root`)**:  
  ~~This is optional unless a pre-installed root certificate is available in the
  `cert/root/<ALGO>/` directory. If the `root` option is not set,
  ensure that this directory contains the following files:~~
  - ~~`cert.pem`~~
  - ~~`privateKey.pem`~~

- **Output Directory (`output-directory`)**:  
  If not provided, the script will save output files to a temporary directory.
  The path to this directory will be displayed in the output.

- **Post-Quantum Cryptography (`pqc`)**:  
  If this option is enabled, the script will utilize a post-quantum
  cryptographic algorithm. For this mode, ensure the `cert` directory includes
  two private key files:
  - `privateKey.pem`
  - `privateKey-pqc.pem`

## Default Behavior

If no optional paths or directories are specified, the script will:
- Default to a `cert` directory in the same location as the script.
- Use a temporary output directory, whose path will be shown in the output
  logs.
