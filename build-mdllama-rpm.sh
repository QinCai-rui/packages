#!/usr/bin/env bash
set -e

# 1. Install build dependencies (Fedora/CentOS/RHEL)
sudo dnf install -y python3 python3-pip python3-wheel python3-setuptools ruby rubygems gcc redhat-rpm-config rpm-build rpmdevtools
# For fpm (Effing Package Management)
gem install --no-document fpm

# 2. Clone mdllama source
git clone https://github.com/QinCai-rui/mdllama.git
cd mdllama/src

# 3. Install Python dependencies for build only (ollama is not in Fedora repos)
pip3 install --user ollama

# 4. Build RPM package with fpm
# Get version from setup.py
tool_version=$(python3 setup.py --version)
fpm -s python -t rpm \
    --python-bin python3 \
    --name mdllama \
    --version "$tool_version" \
    --depends python3 \
    --depends python3-requests \
    --depends python3-rich \
    --architecture noarch \
    --description "A command-line interface for Ollama API" \
    --maintainer "Raymont Qin <hello@qincai.xyz>" \
    --url "https://github.com/QinCai-rui/mdllama" \
    .

# 5. Move the generated .rpm to rpm-out directory for artifact upload
cd ../..
mkdir -p rpm-out
find mdllama/src -name '*.rpm' -exec cp {} rpm-out/ \;

# 6. Clean up
rm -rf mdllama

echo "Done! The RPM package is in the current directory. You can now distribute or upload it to a Fedora repo."
