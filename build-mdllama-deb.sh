#!/usr/bin/env bash
set -e

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y python3-pip devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich dh-python python3-colorama

# 2. Preserve previous built packages
timestamp=$(date +%Y%m%d-%H%M%S)
if [ -d repo ]; then
  mkdir -p repo-backup
  mv repo repo-backup/repo-$timestamp
  echo "Previous repo backed up to repo-backup/repo-$timestamp"
fi

# Backup any existing .deb files
if ls *.deb 1> /dev/null 2>&1; then
  mkdir -p deb-backup
  mv *.deb deb-backup/
  echo "Previous .deb files backed up to deb-backup/"
fi

# 3. Clone mdllama source
git clone https://github.com/QinCai-rui/mdllama.git

# 4. Build .deb package with stdeb
cd mdllama/src
cat > stdeb.cfg <<EOF
[stdeb]
Suite = stable
Architecture = all
Depends = python3, python3-requests, python3-rich, python3-colorama
EOF

# Build the package using the new modular structure
python3 setup.py --command-packages=stdeb.command bdist_deb
cd ../..

# 5. Move the generated .deb to workspace root
find mdllama/src -name '*.deb' -exec cp {} . \;

# 6. Prepare APT repo structure
# Preserve existing packages from backup if they exist
if [ -d "repo-backup/repo-$timestamp/pool/main/m/mdllama" ]; then
  mkdir -p repo/pool/main/m/mdllama
  cp repo-backup/repo-$timestamp/pool/main/m/mdllama/*.deb repo/pool/main/m/mdllama/ 2>/dev/null || true
  echo "Preserved existing packages from previous repo"
else
  mkdir -p repo/pool/main/m/mdllama
fi
mkdir -p repo/dists/stable/main/binary-all

# Add the new .deb packages
cp ./*.deb repo/pool/main/m/mdllama/
echo "Added new packages to repo:"
ls -la repo/pool/main/m/mdllama/

cd repo
dpkg-scanpackages pool /dev/null | tee dists/stable/main/binary-all/Packages | gzip -9c > dists/stable/main/binary-all/Packages.gz

# --- Instead of symlinks, COPY binary-all to all common archs for GitHub Pages compatibility ---
cd dists/stable/main
for arch in binary-amd64 binary-arm64 binary-i386 binary-armhf; do
    rm -rf "$arch"
    cp -r binary-all "$arch"
done
cd ../../../../

# Generate Release file with required metadata
mkdir -p repo/dists/stable
cat > repo/apt-ftparchive.conf <<EOF
APT::FTPArchive::Release {
  Origin "Raymont Qin";
  Label "Raymont Qin";
  Suite "stable";
  Codename "stable";
  Architectures "all amd64 arm64 i386 armhf";
  Components "main";
  Description "Raymont's personal PPA";
};
EOF

cd repo
apt-ftparchive -c=apt-ftparchive.conf release dists/stable > dists/stable/Release

# === FIX: Generate empty compressed translation and contents files in correct locations ===

# Translation files (.bz2), only need one copy each
mkdir -p dists/stable/main/i18n
echo | bzip2 > dists/stable/main/i18n/Translation-en.bz2
echo | bzip2 > dists/stable/main/i18n/Translation-en_GB.bz2

# Contents files (.gz), one per arch and for "all"
for arch in all amd64 arm64 armhf i386; do
    echo | gzip > dists/stable/main/Contents-${arch}.gz
done

# Remove any uncompressed or wrongly placed Contents/Translation files
find . -type f \( -name "Contents-*" ! -name "*.gz" -o -name "Translation-en" -o -name "Translation-en_GB" \) -delete

cd ..

# Clean up
rm -rf mdllama

echo "Done! The repo is in ./repo. Deploy it to your gh-pages branch for PPA hosting."
