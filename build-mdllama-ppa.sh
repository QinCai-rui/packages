#!/usr/bin/env bash
set -e

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich
# ollama is not in official repos, so install via pip for build only
pip3 install ollama --break-system-packages

# 2. Clone mdllama source
git clone https://github.com/QinCai-rui/mdllama.git

# 3. Build .deb package with stdeb
cd mdllama/src
cat > stdeb.cfg <<EOF
[stdeb]
Suite = stable
Architecture = all
Depends = python3, python3-requests, python3-ollama, python3-rich
EOF
python3 setup.py --command-packages=stdeb.command bdist_deb
cd ../..

# 4. Move the generated .deb to workspace root
find mdllama/src -name '*.deb' -exec cp {} . \;

# 5. Prepare APT repo structure
rm -rf repo
mkdir -p repo/pool/main/m/mdllama
mkdir -p repo/dists/stable/main/binary-all
cp ./*.deb repo/pool/main/m/mdllama/
cd repo
dpkg-scanpackages pool /dev/null | gzip -9c > dists/stable/main/binary-all/Packages.gz
apt-ftparchive release dists/stable > dists/stable/Release
cd ..

echo "Done! The repo is in ./repo. Deploy it to your gh-pages branch for PPA hosting."
