#!/usr/bin/env bash

set -e

# Clean up old rpm-out directory before build
rm -rf rpm-out/

# 1. Install build dependencies (Fedora/CentOS/RHEL)
sudo dnf install -y \
  python3 python3-pip python3-wheel python3-setuptools \
  ruby rubygems gcc redhat-rpm-config rpm-build rpmdevtools createrepo_c python3-colorama

# For fpm (Effing Package Management)
gem install --no-document fpm

# 2. Upgrade pip and install Python build dependencies via pip
python3 -m pip install --upgrade pip wheel

# 3. Install ollama from PyPI (not available as a system package)
python3 -m pip install --user ollama

# 4. Clone mdllama source
git clone https://github.com/QinCai-rui/mdllama.git
cd mdllama/src

# Fix pyproject.toml license format
sed -i 's/license = "GPL-3.0-only"/license = {text = "GPL-3.0-only"}/' pyproject.toml

# 5. Build RPM package with wheel+pip+fpm (fixes entry point)
# Get version from setup.py
tool_version=$(python3 setup.py --version)
rm -rf pkgroot

# Install the package with the new modular structure
python3 setup.py install --root "$PWD/pkgroot"

# Create the RPM package
fpm -s dir -t rpm \
    -n python3-mdllama \
    -v "$tool_version" \
    --architecture noarch \
    --depends python3 \
    --depends python3-requests \
    --depends python3-rich \
    --depends python3-colorama \
    --depends python3-setuptools \
    --depends python3-pkg-resources \
    --no-auto-depends \
    --description "A command-line interface for Ollama and OpenAI-compatible API" \
    --maintainer "Raymont Qin <hello@qincai.xyz>" \
    --url "https://github.com/QinCai-rui/mdllama" \
    -C pkgroot .

# 6. Move the generated .rpm to rpm-out directory for artifact upload
cd ../..

OLD_STABLE_RPM_DIR="oldrepo/fedora"
mkdir -p rpm-out
if [ -d "$OLD_STABLE_RPM_DIR" ]; then
  cp $OLD_STABLE_RPM_DIR/*.rpm rpm-out/ 2>/dev/null || true
  echo "Copied existing RPMs from gh-pages oldrepo/fedora."
fi

echo "All RPM packages in repo (old + new):"

# Remove duplicate RPMs (keep all unique versions)
find rpm-out/ -type f -name '*.rpm' | sort | uniq -d | xargs -r rm -v
# Add the new .rpm packages
find mdllama/src -name '*.rpm' -exec cp {} rpm-out/ \;
echo "All RPM packages in repo (old + new):"
ls -la rpm-out/

# 7. Generate YUM repo metadata
if command -v createrepo_c >/dev/null 2>&1; then
  createrepo_c rpm-out/
else
  echo "Warning: createrepo_c not found, skipping repo metadata generation. DNF/YUM repo will not work!" >&2
fi

# 8. Clean up
rm -rf mdllama
sudo pip uninstall mdllama -y

echo "Done! The RPM package and repo metadata are in rpm-out/. You can now distribute or upload it to a Fedora repo."