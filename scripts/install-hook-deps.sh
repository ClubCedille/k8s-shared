#!/usr/bin/env bash
# Installe, sans sudo, les binaires requis par .pre-commit-config.yaml qui ne
# sont pas des paquets standards des distros (Arch/Ubuntu/Fedora/...) :
# tflint, kubeconform, pluto, kube-score. Mêmes versions que la CI
# (clubcedille/cedille-workflows), installés dans ~/.local/bin.
#
# kubectl, pre-commit et terraform/opentofu NE sont PAS installés ici -- ce
# sont des paquets standards, à installer via le gestionnaire de paquets de
# ta distro (ou pip/pipx pour pre-commit) :
#
#   Arch / Manjaro   : sudo pacman -S kubectl opentofu pre-commit
#   Ubuntu / Debian   : sudo apt install kubectl pre-commit   # terraform/opentofu :
#                       voir https://opentofu.org/docs/intro/install/#linux-package-manager
#   Fedora / RHEL     : sudo dnf install kubectl pre-commit terraform
#   n'importe où      : pipx install pre-commit
#
# Note : les hooks Terraform (antonbabenko/pre-commit-terraform) détectent
# automatiquement OpenTofu si `terraform` n'est pas sur le PATH -- avoir
# uniquement `tofu` installé fonctionne sans configuration supplémentaire.

set -euo pipefail

TFLINT_VERSION="0.53.0"
KUBECONFORM_VERSION="0.8.0"
PLUTO_VERSION="5.24.0"
KUBE_SCORE_VERSION="1.20.0"

bin_dir="${HOOK_DEPS_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$bin_dir"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *)
    echo "Architecture non supportée par ce script : $arch" >&2
    exit 1
    ;;
esac

if [ "$os" != "linux" ] && [ "$os" != "darwin" ]; then
  echo "OS non supporté par ce script : $os" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> tflint v${TFLINT_VERSION}"
curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_${os}_${arch}.zip" -o "$tmp/tflint.zip"
unzip -oq "$tmp/tflint.zip" -d "$bin_dir"
chmod +x "$bin_dir/tflint"

echo "==> kubeconform v${KUBECONFORM_VERSION}"
curl -fsSL "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-${os}-${arch}.tar.gz" |
  tar xz -C "$bin_dir" kubeconform

echo "==> pluto v${PLUTO_VERSION}"
curl -fsSL "https://github.com/FairwindsOps/pluto/releases/download/v${PLUTO_VERSION}/pluto_${PLUTO_VERSION}_${os}_${arch}.tar.gz" |
  tar xz -C "$bin_dir" pluto

echo "==> kube-score v${KUBE_SCORE_VERSION}"
curl -fsSL "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VERSION}/kube-score_${KUBE_SCORE_VERSION}_${os}_${arch}" \
  -o "$bin_dir/kube-score"
chmod +x "$bin_dir/kube-score"

echo
echo "Installé dans $bin_dir :"
ls -1 "$bin_dir" | grep -E '^(tflint|kubeconform|pluto|kube-score)$'
echo
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "⚠️  $bin_dir n'est pas dans ton PATH -- ajoute-le dans ton shell rc." ;;
esac
