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
mkdir -p repo/dists/stable/main/binary-all
cp ./*.deb repo/pool/main/m/mdllama/

cd repo
dpkg-scanpackages pool /dev/null | tee dists/stable/main/binary-all/Packages | gzip -9c > dists/stable/main/binary-all/Packages.gz

# Symlink binary-all to other common archs to avoid apt warnings
cd dists/stable/main
for arch in binary-amd64 binary-arm64 binary-i386 binary-armhf; do
    ln -sfn binary-all "$arch"
done
cd ../../../../

# Ensure dists/stable exists to avoid "No such file or directory" error
mkdir -p dists/stable

# Generate Release file with required metadata
cat > apt-ftparchive.conf <<EOF
APT::FTPArchive::Release {
  Origin "Raymont Qin";
  Label "Raymont Qin";
  Suite "stable";
  Codename "stable";
  Architectures "all amd64 arm64 i386 armhf";
  Components "main";
  Description "Raymont's custom PPA";
};
EOF

apt-ftparchive -c=apt-ftparchive.conf release dists/stable > dists/stable/Release

cd ..

rm -rf mdllama

echo "Done! The repo is in ./repo. Deploy it to your gh-pages branch for PPA hosting."