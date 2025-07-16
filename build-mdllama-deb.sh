#!/usr/bin/env bash
set -e

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y python3-pip devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich dh-python python3-colorama

# 2. Clone mdllama source
git clone https://github.com/QinCai-rui/mdllama.git

# 3. Build .deb package with stdeb
cd mdllama/src
cat > stdeb.cfg <<EOF
[stdeb]
Suite = stable
Architecture = all
Depends = python3, python3-requests, python3-rich, python3-colorama
EOF

python3 setup.py --command-packages=stdeb.command bdist_deb
cd ../..

# 4. Move the generated .deb to workspace root
find mdllama/src -name '*.deb' -exec cp {} . \;

# 5. Prepare APT repo structure

# Ensure top-level repo directory always exists first
mkdir -p repo

# Restore all previously published DEBs from gh-pages clone (if available)
if [ -d oldrepo/debian/pool/main/m/mdllama ]; then
  mkdir -p repo/pool/main/m/mdllama
  cp oldrepo/debian/pool/main/m/mdllama/*.deb repo/pool/main/m/mdllama/ 2>/dev/null || true
  echo "Copied existing DEBs from gh-pages oldrepo/debian directory."
else
  mkdir -p repo/pool/main/m/mdllama
fi

# Ensure repo subdirectories exist
mkdir -p repo/dists/stable/main/binary-all

# Add the new .deb packages
cp ./*.deb repo/pool/main/m/mdllama/
echo "Added new packages to repo:"
ls -la repo/pool/main/m/mdllama/

# Remove duplicate .deb files in pool (keep all unique versions)
cd repo/pool/main/m/mdllama
ls | grep -E '\.deb$' | sort | uniq -d | xargs -r rm -v
cd "$(dirname "$0")"

# Move into repo directory (already ensured to exist above)
cd repo
# Use -m to include all versions in Packages file
dpkg-scanpackages -m pool /dev/null | tee dists/stable/main/binary-all/Packages | gzip -9c > dists/stable/main/binary-all/Packages.gz

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