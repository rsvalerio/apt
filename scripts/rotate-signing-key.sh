#!/usr/bin/env bash
# Generate and export a passphrase-less GPG key for APT repo CI signing.
# See README.md "Rotating the signing key".

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly GPG_WORKDIR="${REPO_ROOT}/.gpg-workdir"
readonly BUILD_DIR="${REPO_ROOT}/build"
readonly BATCH_FILE="${SCRIPT_DIR}/apt-signing.batch"
readonly KEY_ID_FILE="${BUILD_DIR}/key-id.txt"
readonly SECRET_ASC="${BUILD_DIR}/apt-secret.asc"
readonly SECRET_B64="${BUILD_DIR}/apt-secret.b64"
readonly FINGERPRINT_FILE="${BUILD_DIR}/apt-gpg-fingerprint.txt"
readonly PUBLIC_KEY="${REPO_ROOT}/public.key"

export GNUPGHOME="${GPG_WORKDIR}"

signing_key_usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  help            Show this message
  keygen          Create passphrase-less key in .gpg-workdir/
  show-keys       Print key ID and fingerprint
  export-public   Write public.key (commit to git)
  export-secret   Write build/apt-secret.b64 for 1Password / GitHub
  test-sign       Verify signing works without a passphrase
  rotate          Run keygen, export-public, export-secret, test-sign
  clean           Remove .gpg-workdir/ and build/

Examples:
  $(basename "$0") rotate
  $(basename "$0") clean
EOF
}

signing_key_ensure_gpg_homedir() {
  mkdir -p "${GPG_WORKDIR}"
  chmod 700 "${GPG_WORKDIR}"
}

signing_key_ensure_build_dir() {
  mkdir -p "${BUILD_DIR}"
}

signing_key_secure_remove() {
  local path="$1"
  if command -v shred >/dev/null 2>&1; then
    shred -u "${path}"
  elif rm -P -- "${path}" 2>/dev/null; then
    :
  else
    rm -f -- "${path}"
  fi
}

signing_key_exists() {
  gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep -q '^sec'
}

signing_key_require_exists() {
  if ! signing_key_exists; then
    echo "error: no signing key in ${GPG_WORKDIR}; run: $(basename "$0") keygen" >&2
    exit 1
  fi
}

signing_key_generate() {
  signing_key_ensure_gpg_homedir

  if signing_key_exists; then
    echo "Key already present in ${GPG_WORKDIR}; skip keygen or run 'clean' first."
    signing_key_show_metadata
    return 0
  fi

  gpg --batch --generate-key "${BATCH_FILE}"
  signing_key_show_metadata
}

signing_key_show_metadata() {
  signing_key_require_exists
  gpg --list-secret-keys --keyid-format=long
  echo
  gpg --fingerprint --keyid-format=long
}

signing_key_read_id() {
  signing_key_require_exists
  gpg --list-secret-keys --keyid-format=long \
    | awk '/^sec/ { print $2; exit }' | cut -d/ -f2
}

signing_key_cache_id() {
  signing_key_ensure_build_dir
  signing_key_read_id > "${KEY_ID_FILE}"
}

signing_key_cached_id() {
  if [[ ! -f "${KEY_ID_FILE}" ]]; then
    signing_key_cache_id
  fi
  cat "${KEY_ID_FILE}"
}

signing_key_export_public() {
  local key_id
  key_id="$(signing_key_cached_id)"
  gpg --armor --export "${key_id}" > "${PUBLIC_KEY}"
  echo "Wrote ${PUBLIC_KEY} (key ${key_id})"
}

signing_key_export_secret_b64() {
  local key_id
  key_id="$(signing_key_cached_id)"
  signing_key_ensure_build_dir

  gpg --armor --export-secret-keys "${key_id}" > "${SECRET_ASC}"
  base64 < "${SECRET_ASC}" | tr -d '\n' > "${SECRET_B64}"
  signing_key_secure_remove "${SECRET_ASC}"

  echo "Wrote ${SECRET_B64} — 1Password / GitHub secret APT_GPG_PRIVATE_KEY"
  signing_key_write_fingerprint_file
  signing_key_print_copy_commands
}

signing_key_test_signing() {
  local key_id
  key_id="$(signing_key_cached_id)"
  echo test | gpg --batch --yes --local-user "${key_id}" --clearsign > /dev/null
  echo "Signing OK for key ${key_id}"
}

signing_key_print_fingerprint() {
  signing_key_require_exists
  gpg --list-secret-keys --with-colons \
    | awk -F: '/^fpr:/ { print $10; exit }'
}

signing_key_write_fingerprint_file() {
  signing_key_ensure_build_dir
  signing_key_print_fingerprint > "${FINGERPRINT_FILE}"
  echo "Wrote ${FINGERPRINT_FILE} — GitHub variable APT_GPG_KEY_ID"
}

signing_key_print_copy_commands() {
  cat <<EOF

Copy to clipboard:
  '< ${SECRET_B64}|clip'
  '< ${FINGERPRINT_FILE}|clip'
EOF
}

signing_key_print_next_steps() {
  local fingerprint
  fingerprint="$(cat "${FINGERPRINT_FILE}")"

  cat <<EOF

Next steps:
  1. APT_GPG_PRIVATE_KEY  ← ${SECRET_B64}
  2. APT_GPG_KEY_ID       ← ${fingerprint}
  3. Remove APT_GPG_PASSPHRASE from 1Password / Terraform / GitHub
  4. terraform apply  (or update github-pages environment secrets/variables)
  5. git add public.key && git commit && git push
  6. $(basename "$0") clean   (wipe local key material)
EOF

  signing_key_print_copy_commands
}

signing_key_rotate_all() {
  signing_key_generate
  signing_key_export_public
  signing_key_export_secret_b64
  signing_key_test_signing
  signing_key_print_next_steps
}

signing_key_clean_artifacts() {
  rm -rf "${GPG_WORKDIR}" "${BUILD_DIR}"
  echo "Removed ${GPG_WORKDIR} and ${BUILD_DIR}"
}

signing_key_main() {
  local command="${1:-help}"

  case "${command}" in
    help | -h | --help)
      signing_key_usage
      ;;
    keygen)
      signing_key_generate
      ;;
    show-keys)
      signing_key_show_metadata
      ;;
    export-public)
      signing_key_export_public
      ;;
    export-secret)
      signing_key_export_secret_b64
      ;;
    test-sign)
      signing_key_test_signing
      ;;
    rotate)
      signing_key_rotate_all
      ;;
    clean)
      signing_key_clean_artifacts
      ;;
    *)
      echo "error: unknown command: ${command}" >&2
      echo >&2
      signing_key_usage >&2
      exit 1
      ;;
  esac
}

signing_key_main "$@"
