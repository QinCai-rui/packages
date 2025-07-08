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

# --- Instead of symlinks, COPY binary-all to all common archs for GitHub Pages compatibility ---
cd dists/stable/main
for arch in binary-amd64 binary-arm64 binary-i386 binary-armhf; do
    rm -rf "$arch"
    cp -r binary-all "$arch"
done

# Generate empty files to silence apt "Ign" and speed up user experience
for arch in all amd64 arm64 armhf i386; do
    mkdir -p binary-$arch
    touch binary-$arch/Translation-en
    touch binary-$arch/Translation-en_GB
    touch binary-$arch/Contents-$arch
    touch binary-$arch/Contents-all
    touch binary-$arch/Components
done
touch "Icons (48x48)"
touch "Icons (64x64)"
touch "Icons (64x64@2)"
touch "Icons (128x128)"
touch ../Contents-all
touch ../Contents-amd64
touch ../Contents-arm64
touch ../Contents-armhf
touch ../Contents-i386

cd ../../../../

# Ensure file/folder exists to avoid "No such file or directory" error
mkdir -p dists/stable
touch dists/stable/Release

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
