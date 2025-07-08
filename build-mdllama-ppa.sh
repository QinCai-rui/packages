#!/usr/bin/env bash
set -e

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich dh-python

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
# Ensure both binary-all and binary-arm64 are present and populated for arm64 users
mkdir -p repo/dists/stable/main/binary-all
mkdir -p repo/dists/stable/main/binary-arm64
cp ./*.deb repo/pool/main/m/mdllama/

# Generate Packages.gz for both arch dirs (copy if package arch is all)
cd repo
dpkg-scanpackages pool /dev/null | tee dists/stable/main/binary-all/Packages | gzip -9c > dists/stable/main/binary-all/Packages.gz
cp dists/stable/main/binary-all/Packages dists/stable/main/binary-arm64/Packages
cp dists/stable/main/binary-all/Packages.gz dists/stable/main/binary-arm64/Packages.gz

# Generate Release file with required metadata
cat > apt-ftparchive.conf <<EOF
APT::FTPArchive::Release {
  Origin "QinCai-rui";
  Label "QinCai-rui";
  Suite "stable";
  Codename "stable";
  Architectures "all arm64";
  Components "main";
  Description "QinCai-rui custom PPA";
};
EOF

apt-ftparchive -c=apt-ftparchive.conf release dists/stable > dists/stable/Release

cd ..

rm -rf mdllama

echo "Done! The repo is in ./repo. Deploy it to your gh-pages branch for PPA hosting."
